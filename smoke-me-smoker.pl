#!perl -w
use strict;
use POSIX qw(strftime);
use File::Find;
use Config::JSON;
use Data::UUID;
use Data::Dumper;
use FindBin;
use File::Copy;
use Getopt::Long;
use lib "$FindBin::Bin/lib";
use PerlSmoker::Push qw(smoke_queue smoke_push_queued status_push);

my $opt_send_queued;
my $opt_help;
my $opt_one;
my $opt_buildcfg = "default";
my $opt_keep;
my $cfg_file = "smoke.cfg";
GetOptions("s|sendqueued" => \$opt_send_queued,
	   "1|one" => \$opt_one,
	   "b|buildconfig=s" => \$opt_buildcfg,
	   "k|keep" => \$opt_keep,
	   "c|config=s" => \$cfg_file,
	   "h|help" => \$opt_help);

if ($opt_help) {
  print <<EOS;
Usage: $0 [options] [branches]
  -sendqueued, -s - send any queued JSON files and stop
  -one, -1 - smoke one configuration and stop
  -b <build-config>, -buildconfig <build-config>
     - select a built configuration if building explicit branches
       "default" if not supplied
  -c filename, -config filename - smoke configuration file, default smoke.cfg
  -help, -h - display this help text
  branches - branch names excluding the remote name to smoke rather than
    random selection.  Processing terminates when done unless -k is supplied
  -k - keep processing random branches after processing explicit branches
EOS
  exit;
}

if (@ARGV && $opt_one) {
  print "-one is ignored with explicit branches\n";
  $opt_one = 0;
}

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
my $pid_filename = "$base/smoke-me.pid";
my $stop_filename = "$base/smoke-stop";
my $post_key = $cfg->get("postkey") or die "No postkey";
my $remote = $cfg->get('remote') || "origin";
my $smokedb_url = $cfg->get("smokedb_url") || "http://perl5.test-smoke.org/report";

my $queue_dir = $cfg->get("queue") || "$base/queue";
-d $queue_dir or die "$queue_dir isn't a directory";

my $json_dir = $cfg->get("jsondir") || "$base/json";
-d $json_dir or mkdir $json_dir;
-d $json_dir or die "$json_dir is not a directory";

my $json_queue = $cfg->get("jsonqueue") || "$base/jsonqueue";
-d $json_queue or mkdir $json_queue;
-d $json_queue or die "$json_queue is not a directory";

if ($opt_send_queued) {
  if (@ARGV) {
    for my $report (@ARGV) {
      send_one_report($report);
    }
  }
  else {
    deliver_queued_reports();
  }
  exit;
}

if (-f $pid_filename) {
  print "$pid_filename already exists, checking...\n";
  open my $pid_file, "<", $pid_filename
    or die "$pid_filename exists but I can't open it: $!\n";
  my $pid = <$pid_file>;
  chomp $pid;
  if (kill 0, $pid) {
    die "I seem to be already running as process $pid\n";
  }
}

open my $pid_file, ">", $pid_filename
  or die "Cannot create $pid_filename: $!\n";
print $pid_file $$;
close $pid_file;
print "Running as PID $$\n";

my $os = `uname -s`;
chomp $os;
my $arch = `uname -m`;
chomp $arch;
my $host = `uname -n`;
chomp $host;

my $ug = Data::UUID->new;

our $conf;
my $conf_filename = "$smoke/smokecurrent_config";
require $conf_filename;

my %seen;

{
  my @seen = `cat $seen_file`;
  chomp @seen;
  %seen = map { split ' ' } @seen;
};

my %cfgs = %{$cfg->get("configs")};

my @cfg_names = keys %cfgs;

if (@ARGV) {
  unless ($cfgs{$opt_buildcfg}) {
    die "Unknown configuration '$opt_buildcfg'\n";
  }
}

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

# keep looping unless a branch is supplied
my $forever = $opt_keep || @ARGV == 0;

while ($forever || @ARGV) {
  my $did_run = 0;
  my $good = eval {
    -e "$smoke/smokecurrent.lck"
      and die "Smoker locked, remove lock file";

    print "\n-- Cleaning up and querying state\n";

    chdir $gitbase or die "chdir $gitbase: $!\n";
    system "git clean -dxf"
      and die "PERM: git clean\n";
    system "git reset --hard HEAD"
      and die "PERM: git reset\n";
    system "git fetch $remote"
      and die "TEMP: git fetch\n";
    system "git remote prune $remote"
      and die "PERM: git prune\n";
    system "git checkout blead"
      and die "git checkout blead";
    system "git rebase $remote/blead"
      and die "git rebase $remote/blead";
    my @branches = map substr($_, 2), `git branch -r`;
    chomp @branches;

    # remove any local branches that aren't blead
    my @local = map substr($_, 2), `git branch`;
    chomp @local;
    for my $branch (grep $_ ne 'blead', @local) {
      print "Removing stale local branch '$branch'\n";
      system "git", "branch", "-D", $branch
	and die "Cannot remove branch $branch";
    }

    print "\n-- Looking for work\n";

    # earlier 30 days ago
    my $mindate = strftime("%Y-%m-%d", localtime(time() - 30 * 86_400));
    my @smokeme = grep m(^$remote/smoke[-_]me/[a-zA-Z0-9/_+.-]+\z), @branches;

    my %shas;
    my %dates;
    for my $branch (@smokeme, @other_branches) {
      $shas{$branch} = branch_patch($branch);
      $dates{$branch} = branch_date($branch);
    }

    my @cand;

    if (@ARGV) {
      my $local = shift @ARGV;
      my $branch = "$remote/$local";

      my $found = 0;
      unless (grep $_ eq $branch, @branches) {
	die "$branch not found on $remote\n";
      }
      push @cand, [ $branch, $opt_buildcfg ];
    }

    
    # eliminate old branches
    my @cand_smokeme = grep $dates{$_} ge $mindate, @smokeme;
    my @cand_other = grep $dates{$_} ge $mindate, @other_branches;
      
    # is there a smoke-me available for default smoking
    unless (@cand) {
      {
	my @def_smokeme = grep !$seen{"$shas{$_}-default"}, @cand_smokeme;
	if (@def_smokeme) {
	  print "smoke-me: @def_smokeme\n";
	  push @cand, [ $def_smokeme[rand @def_smokeme], "default" ];
	}
      }
      # is an "other" available for default smoking
      {
	my @def_other = grep !$seen{"$shas{$_}-default"}, @cand_other;
	if (@def_other) {
	  print "other: @def_other\n";
	  push @cand, [ $def_other[rand @def_other], "default" ];
	}
      }
    }

    unless (@cand) {
      print "\n-- No default configs to smoke, looking harder\n";
      {
	# look for a smoke-me with an unsmoked config
	my @nondef_smokeme;
	for my $branch (@cand_smokeme) {
	  my $bpatch = $shas{$branch};
	  for my $ccfg (@cfg_names) {
	    push @nondef_smokeme, [ $branch, $ccfg]
	      unless $seen{"$bpatch-$ccfg"};
	  }
	}
	
	if (@nondef_smokeme) {
	  push @cand, $nondef_smokeme[rand @nondef_smokeme]
	}
      }

      {
	# look for an "other" with an un-smoked config
	my @nondef_other;
	for my $branch (@cand_other) {
	  my $bpatch = $shas{$branch};
	  for my $ccfg (@cfg_names) {
	    push @nondef_other, [ $branch, $ccfg]
	      unless $seen{"$bpatch-$ccfg"};
	  }
	}

	if (@nondef_other) {
	  push @cand, $nondef_other[rand @nondef_other];
	}
      }
    }

    @cand
      or return 1; # nothing to do

    print "-- Candidate: $_->[1] $_->[0]\n" for @cand;
    print "\n-- Flipping a coin...\n" if @cand > 1;

    my $cand = $cand[rand @cand];
    my ($which, $cfg) = @$cand;

    (my $local = $which) =~ s(^$remote/)();

    print "\n-- Found $cfg $local\n";

    my $patch = $shas{$which};

    my $uuid = $ug->create_str;
    set_user_note(<<EOS);
UUID: $uuid
Branch: $local
Config: $cfg
Logs: http://perl.develop-help.com/reports/
EOS

    status_push
      (
       host => $host,
       status => "smoking",
       smoke => "$which-$cfg/$patch",
       key => $post_key,
      );

    # setup the branch
    chdir $gitbase
      or die "PERM: chdir $gitbase: $!\n";

    unless ($local eq "blead") {
      system "git", "checkout", "-b", $local, $which
	and die "PERM: git checkout -b $local $which";
    }
    system "$^X Porting/make_dot_patch.pl >.patch"
      and die "PERM: make_dot_patch\n";

    # do our own rsync here
    -d $build_dir or mkdir $build_dir;
    system "rsync", "-a", "--delete", "$gitbase/", "$build_dir/"
      and die "PERM: rsync -a --delete $gitbase/ $build_dir/";

    my $cfg_opts = $cfgs{$cfg}{config};
    print "\n-- Smoking $local-$cfg/$patch...\n";
    system "cd $smoke && ./smokecurrent.sh -nosmartsmoke -nomail -nosend $cfg_opts </dev/null";
    #or die "smoke error";
    $did_run = 1;

    print "\n-- Smoke complete, sending mail report\nUUID: $uuid\n";

    system "cd $smoke && $^X mailrpt.pl -c smokecurrent_config";

    my $jsonfile = "$build_dir/mktest.jsn";
    
    -f $jsonfile
      or die "PERM: No $jsonfile found after sendrpt.pl";
    my $queued_json = "$json_queue/$uuid.jsn";
    copy($jsonfile, $queued_json)
      or die "PERM: Cannot copy $jsonfile to $queued_json: $@\n";
    my $arch_json = "$json_dir/$uuid.jsn";
    copy($jsonfile, $arch_json)
      or die "PERM: Cannot copy $jsonfile to $arch_json: $@\n";

    print "\n-- Posting to site\n";
    my $log = "$smoke/smokecurrent.log";
    my $log_gz = $log . ".gz";
    system "gzip <$log >$log_gz";

    my $report_name = "$build_dir/mktest.rpt";

#    my $report;
#    open $report, ">>", $report_name;
#    print $report "\nLogs at http://perl.develop-help.com/reports/\n";
#    print $report "Branch: $which\n";
#    print $report "Configuration: $cfg\n";
#    close $report;

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
       uuid => $uuid,
       key => $post_key,
       _queue => $queue_dir,
      );
    smoke_queue(%opts);

    print "\n-- Sending JSON report\n";

    # -noreport since we should alread have one
    my $send_status = system "cd $build_dir && $^X $smoke/sendrpt.pl -v 10 --noreport --first -d $build_dir -u $smokedb_url";

    if ($send_status == (0 << 8)) {
      # remove the queued JSON, all is good
      unlink $queued_json
	or die "Cannot remove $queued_json: $!";
    }
    elsif ($send_status == (1 << 8)) {
      print "Communication error sending JSON, leaving $queued_json in queue\n";
    }
    elsif ($send_status == (2 << 8)) {
      die "Server returned an error, aborting\n";
    }
    elsif ($send_status == (3 << 8)) {
      die "Server returned an unexpected value, aborting\n";
    }
    else {
      die "sendrpt returned an unexpected result ($send_status), aborting\n";
    }

    $seen{"$patch-$cfg"} = time;

    smoke_push_queued($queue_dir, $post_key);

    # if we get here we have internet, send any queued json
    deliver_queued_reports();

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
    my @del = grep $seen{$_} < time() - $seen_age, keys %seen;
    print "Seen cleanup @del\n" if @del;
    delete @seen{@del};
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

  if ($opt_one || -f $stop_filename) {
    status_push
      (
       host => $host,
       status => "stopped",
       key => $post_key,
      );
    exit;
  }
  unless ($did_run) {
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

  my $entry = `git rev-list --max-count=1 $branch`
    or return;
  chomp $entry;

  return $entry;
}

# get the last commit date for a branch as YYYY-MM-DD
sub branch_date {
  my ($branch) = @_;

  my $entry = `git log -n1 --pretty=format:%cd --date=short $branch`
    or return;
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

sub set_user_note {
  my ($note) = @_;

  my $conf_back = $conf_filename . ".orig";
  unless (-f $conf_back) {
    rename $conf_filename, $conf_back
      or die "PERM: couldn't rename $conf_filename to $conf_back: $!";
  }

  my %work = %$conf;
  $work{user_note} = $note;
  my $dd = Data::Dumper->new([ \%work ], [ 'conf' ]);
  open my $conf_file, ">", $conf_filename
    or die "PERM: couldn't overwrite $conf_filename: $!";
  print $conf_file $dd->Dump;
  close $conf_file
    or die "PERM: cannot close $conf_filename: $!";
}

sub deliver_queued_reports {
  opendir my $dir, $json_queue
    or die "Cannot open $json_queue for delivery: $!";
  while (defined(my $entry = readdir $dir)) {
    $entry =~ /\.jsn$/ or next;
    send_one_report($entry);
  }
  closedir $dir;
}

sub send_one_report {
  my ($entry) = @_;

  my $ua = LWP::UserAgent->new(
      agent => "smoke-me-smoker.pl/1.000",
      );
  my $full = File::Spec->catfile($json_queue, $entry);
  open my $jsnfile, "<", $full
    or die "Cannot open $full for read: $!";
  binmode $jsnfile;
  my $json = do { local $/; <$jsnfile> };
  close $jsnfile;
  print "Attempting to submit queued report $entry\n";
  print substr($json, 0, 200), "\n";
  my $response = $ua->post($smokedb_url, { json => $json });
  unless ($response->is_success) {
    print "Response indicates failure\n";
    die "TEMP: error submitting queued data: ", $response->status_line, "\n";
  }
  print "Response: ", $response->content, "\n";

  my $result;
  my $decoder = JSON->new;
  if (eval { $result = $decoder->decode($response->content); 1 }) {
    if ($result->{error}) {
      if ($result->{error} eq 'Report already posted.') {
	# if we got the job id back I'd report it here
	# treat this as success
	print "Duplicate report, considered successful.\n";
      }
      else {
	die "Error: $result->{error}\n";
      }
    }
    elsif ($result->{id}) {
      print "Reported: $result->{id}\n";
    }
    else {
      # something is broken
      die "Unexpected response\n";
    }
  }
  else {
    die "Invalid JSON response: $@\n";
  }
  
  unlink $full;
}
