package PerlSmokeMe::App;
use v5.36;
use builtin qw(true false);
use Getopt::Long qw(GetOptionsFromArray :config no_permute bundling);

use PerlSmokeMe::Cfg;
use PerlSmokeMe::Git;
use PerlSmokeMe::Done;
use PerlSmokeMe::Matcher;
use PerlSmokeMe::Invoker;

sub new ($class, $argv) {
    my $cfg_file = "$FindBin::Bin/smoke-me.cfg";

    my $verbose = 0;
    my $active = 0;
    GetOptionsFromArray(
        $argv,
        "c|config=s" => \$cfg_file,
        "v+" => \$verbose,
        "a|active!" => \$active);

    my $cfg = PerlSmokeMe::Cfg->new($cfg_file);
    my $git = PerlSmokeMe::Git->new(dir => $cfg->gitbase);
    my $seen = PerlSmokeMe::Done->new($cfg->seen, $cfg->seen_age);
    my @brules = $cfg->branch_rules;
    my @crules = $cfg->config_rules;
    my $matcher = PerlSmokeMe::Matcher->new($seen, \@brules, \@crules, $verbose);
    my $invoker = PerlSmokeMe::Invoker->new($cfg);
    $seen->set_save($active);
    $invoker->set_real($active);
    bless {
        cfg => $cfg,
        git => $git,
        seen => $seen,
        brules => \@brules,
        crules => \@crules,
        matcher => $matcher,
        invoker => $invoker,
        verbose => 1,
    }, $class;
}

sub run ($class, $argv) {
    $class->new($argv)->cmd($argv);
}

sub cmd ($self, $argv) {
    my $cmd = shift @$argv;
    defined $cmd
        or $self->usage;
    if ($cmd eq "run") {
        return $self->cmd_run($argv);
    }
    elsif ($cmd eq "help") {
        $self->cmd_help($argv);
    }
    else {
        print "Unknown command '$cmd'\n";
    }
}

# normally we delay a little between job scans if we don't find
# a job, this delay is suppressed when $last is true
sub _do_one ($self, $last) {
    my $cfg = $self->{cfg};
    my $git = $self->{git};
    my $matcher = $self->{matcher};
    my $invoker = $self->{invoker};
    my $seen = $self->{seen};
    
    $git->fetch($cfg->gitfetchopts);
    my @branches = $git->branches;
    my ($branch, $config) = $matcher->match(\@branches);
    if ($branch) {
        my $bname = $branch->name;
        my $sha = $branch->sha;
        print <<~JOB;
            Found job:
               branch: $bname ($sha)
               config: $config->{name} ($config->{file})
            JOB
        $invoker->invoke($branch->name, $config);
        $seen->saw($branch->sha, $config->{name});
    }
    else {
        if ($last) {
            print "No job found\n";
        }
        else {
            print "No job found - waiting\n";
            sleep 300;
        }
    }
}

sub cmd_run ($self, $argv) {
    my $total_count = 0; # forever
    GetOptionsFromArray(
        $argv,
        "c|count=i" => \$total_count);
    @$argv
        and die "No use for extra @$argv arguments";
    my $done_count = 0;
    my $last = false;
    do {
        $last = $total_count != 0 && ++$done_count >= $total_count;
        $self->_do_one($last);
    } until ($last);
    0;
}

sub cmd_help ($self, $argv) {
    my $cmd = shift @$argv
        or $self->usage;

    if ($cmd eq "run") {
        print <<"EOS";
perl $0 [globaloptions] run [-c count]
  Run count smokes, default is to run forever
EOS
    }
    elsif ($cmd eq "help") {
        print <<"EOS"
perl $0 help
  Display general usage
perl $0 help cmd
  Display help for command cmd
EOS
    }
}

sub usage ($self) {
    print STDERR <<"EOS";
Usage:
  $0 [global options] <cmd> ...
   global options are zero or more of the following:
   -c file - select a config file (default $FindBin::Bin/smoke-me.cfg)
   -a - actual run, otherwise just prints
   -v - verbosity, -vv more verbose, -vvvvvv very verbose
  $0 run       - run smokes
  $0 help      - display this text
  $0 help cmd  - help for cmd
EOS
    exit 1;
}

1;
