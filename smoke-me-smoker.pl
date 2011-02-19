#!perl -w
use strict;
use POSIX qw(strftime);
use File::Find;
use Config::JSON;
use FindBin;
use lib "$FindBin::Bin/lib";
use PerlSmoker::Push qw(smoke_push status_push);

my $cfg_file = shift || "smokeme.cfg";

my $cfg = Config::JSON->new($cfg_file);

my $base = $cfg->get("base");
my $gitbase = $cfg->get("gitbase") || "$base/perl";
my $copy = $cfg->get("copy") || "$base/copy";
my $smoke = $cfg->get("smoke") || "$base/smoke";
my $build_dir = $cfg->get("build") || "$base/perl-current";
my $dot_patch = "$copy/.patch";
my $seen_file = "$base/seen.txt";
my $seen_file_tmp = "$base/seen.txt.work";
my $seen_age = 86_400 * 365;
my $post_key = $cfg->get("postkey") or die "No postkey";

my $gitfetchopts = $cfg->get("gitfetchopts") // '';

my $queue_dir = $cfg->get("queue") || "$base/queue";
-d $queue_dir or die "$queue_dir isn't a directory";

my $os = `uname -s`;
chomp $os;
my $arch = `uname -m`;
chomp $arch;
my $host = `uname -n`;
chomp $host;

my %seen;

{
  my @seen = `cat $seen_file`;
  chomp @seen;
  %seen = map { split ' ' } @seen;
};

my %cfgs = %{$cfg->get("configs")};

my @cfg_names = keys %cfgs;

my @other_branches = @{$cfg->get("others")};
my @others;
for my $branch (@other_branches) {
  push @others, map [ $branch, $_ ], @cfg_names;
}

# use Data::Dumper;
# $Data::Dumper::Terse = 1;
# print "others: ", Dumper \@others;

# print "base: $base\n";
# print "cfgs: ", Dumper(\%cfgs), "\n";
# print "gitbase: $gitbase\n";
# print "copy: $copy\n";
# print "smoke: $smoke\n";
# print "build: $build_dir\n";
# print "patch: $dot_patch\n";
# print "seen: $seen_file\n";
# print "post: $post_key\n";

while (1) {
  my $did_run = 0;
  my $good = eval {
    chdir $gitbase or die "chdir $gitbase: $!\n";
    system "git clean -dxf";
    system "git fetch $gitfetchopts"
      and die "TEMP: git fetch\n";
    system "git checkout blead"
      and die "git checkout blead";
    system "git merge origin/blead"
      and die "git merge origin/blead";
    my @branches = map substr($_, 2), `git branch -a`;
    chomp @branches;

    my $cfg;
    my $which;
    my @smokeme = grep m(origin/smoke[-_]me/), @branches;

    my @cand = grep !$seen{branch_patch($_). "-default"}, @smokeme;
    if (@cand) {
      $cfg = "default";
      $which = $cand[rand @cand];
    }

    unless ($which) {
      # look for an alt branch
      @cand = grep !$seen{branch_patch($_) . "-default"}, @other_branches;

      if (@cand) {
	$cfg = "default";
	$which = $cand[rand @cand];
      }
    }

    unless ($which) {
      # look for an alt cfg smoke-me
      my @cand;
      for my $branch (@smokeme) {
	my $bpatch = branch_patch($branch);
	for my $ccfg (@cfg_names) {
	  push @cand, [ $branch, $ccfg ]
	    unless $seen{"$bpatch-$ccfg"};
	}
      }

      if (@cand) {
	($which, $cfg) = @{$cand[rand @cand]};
      }
    }

    unless ($which) {
      my @cand = grep !$seen{branch_patch($_->[0]) . "-" . $_->[1]}, @others;

      if (@cand) {
	($which, $cfg) = @{$cand[rand @cand]};
      }
    }

    $which or return 1;

    # clean up old extract
    if (-d $copy) {
      system "rm -rf $copy"
	and die "rm -rf $copy";
    }
    my $patch = branch_patch($which);
    print "Extracting $which (", substr($patch, 0, 20), ")\n";
    # extract it
    system "git archive --format=tar --prefix=copy/ $which | tar -x -C $base -f -"
      and die "git archive";

    # strip any .gitignore
    find(sub {
	   $_ eq '.gitignore' and unlink;
	 }, $copy);

    status_push
      (
       host => $host,
       status => "smoking",
       smoke => "$which-$cfg/$patch",
       key => $post_key,
      );
    fake_patch($dot_patch, $which, $patch);
    -e "$smoke/smokecurrent.lck"
      and die "Smoker locked, remove lock file";
    my $cfg_opts = $cfgs{$cfg}{config};
    print "Smoking $which-$cfg/$patch...\n";
    system "cd $smoke && ./smokecurrent.sh -nosmartsmoke -nomail $cfg_opts";
    #or die "smoke error";
    $did_run = 1;

    $seen{"$patch-$cfg"} = time;

    print "Posting to site\n";
    my $log = "$smoke/smokecurrent.log";
    my $log_gz = $log . ".gz";
    system "gzip <$log >$log_gz";

    my $report_name = "$build_dir/mktest.rpt";

    my $report;
    open $report, ">>", $report_name;
    print $report "\nLogs at http://perl.develop-help.com/reports/\n";
    print $report "Branch: $which\n";
    print $report "Configuration: $cfg\n";
    close $report;

    system "cd $smoke && ./mailrpt.pl -c smokecurrent_config";

    my %opts =
      (
       cfg => $cfg,
       branch => $which,
       sha => $patch,
       log => $log_gz,
       out => "$build_dir/mktest.out",
       rpt => $report_name,
       os => $os,
       arch => $arch,
       host => $host,
       when => strftime("%Y-%m-%d %H:%M:%S", gmtime),
       key => $post_key,
       _queue => $queue_dir,
      );
    smoke_push(%opts);

    1;
  };
  unless ($good) {
    my $error = $@;
    unless ($error =~ s/^TEMP://) {
      die $error;
    }
    print "Temporary (?) error: $@  ";
  }

  {
    open my $seen_fh, ">", $seen_file_tmp or die "Create $seen_file_tmp: $!";
    for my $key (keys %seen) {
      print $seen_fh "$key $seen{$key}\n";
    }
    close $seen_fh;
    rename $seen_file_tmp, $seen_file
      or die "Cannot rename $seen_file_tmp to $seen_file: $!";
  }

  unless ($did_run) {
    {
      my @del = grep $seen{$_} < time() - $seen_age, keys %seen;
      print "Seen cleanup @del\n" if @del;
      delete @seen{@del};
    }
    status_push
      (
       host => $host,
       status => "idle",
       key => $post_key,
      );
    print "Nothing to do, waiting\n";
    sleep 600;
  }
}

# get the sha1 for each patch
# must be called with cwd in git checkout
sub branch_patch {
  my ($branch) = @_;

  my $entry = `git rev-list --max-count=1 $branch`;
  chomp $entry;

  return $entry;
}

# fake up a .patch file
sub fake_patch {
  my ($out, $branch, $patch) = @_;

  (my $out_branch = $branch) =~ s(^(?:remotes/)?origin/)();
  my ($desc) = `git describe $branch`;
  chomp $desc;

  my $tstamp = `git log -1 --pretty="format:%ct" $patch`;
  my $when = strftime "%Y-%m-%d.%H:%M:%S",gmtime($tstamp || time);
  open my $pf, ">", $out or die "Cannot create $out: $!";
  
  print $pf "$out_branch $when $patch $desc\n";
  close $pf;
}
