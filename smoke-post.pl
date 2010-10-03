#!/usr/bin/perl
use strict;
use lib '/home/perlsmoke/lib';
use PerlSmoker::Push qw(smoke_push);
use Getopt::Long;

my $log;
my $rpt;
my $out;
my $sha;
my $arch;
my $branch;
my $os;
my $host;
my $when;
my $cfg;
GetOptions
  (
   "log=s" => \$log,
   "rpt=s" => \$rpt,
   "out=s" => \$out,
   "sha=s" => \$sha,
   "branch=s" => \$branch,
   "os=s" => \$os,
   "host=s" => \$host,
   "arch=s" => \$arch,
   "when=s" => \$when,
   "cfg=s" => \$cfg,
  );

defined $log or die;
-f $log or die;
my $log_gz = "$log.gz";
unlink $log_gz;
system "gzip <$log >$log_gz"
  and die;

defined $rpt or die;
-f $rpt or die;

defined $out or die;
-f $out or die;

defined $sha or die;

defined $branch or die;

defined $os or die;

defined $host or die;

defined $arch or die;

defined $when or die;

defined $cfg or die;

smoke_push(log => $log_gz,
	   rpt => $rpt,
	   out => $out,
	   sha => $sha,
	   branch => $branch,
	   os => $os,
	   host => $host,
	   arch => $arch,
	   when => $when,
	   cfg => $cfg);
