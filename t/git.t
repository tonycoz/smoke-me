#!perl
use v5.36;
use PerlSmokeMe::Git;
use Test::More;

my $perl = $ENV{PERL_TREE}
    or plan skip_all => "no PERL_TREE defined";
-d $perl && -d "$perl/.git" && -f "$perl/perl.h"
    or plan skip_all => "PERL_TREE $perl not a perl checkout";

my $git = PerlSmokeMe::Git->new(dir => $perl);
ok($git->fetch, "can fetch");
my @branches = $git->branches;
ok(@branches, "got some branches");
note $_->name for @branches;
my ($blead) = grep { $_->name eq "blead" } @branches;
ok($blead, "have blead");
cmp_ok($blead->epoch, '>', time() - 30 * 86400, "blead is vaguely recent");

my ($maint40) = grep { $_->name eq "maint-5.40" } @branches;
ok($maint40, "have maint-5.40");

my ($maint004) = grep { $_->name eq "maint-5.004" } @branches;
ok($maint004, "have maint-5.004");
# don't expect this to change
is($maint004->sha, "8f5b92120b4b3b9ea30d15d7b597b3d208487a26",
   "got expected sha for 5.004");
is($maint004->epoch, 1229688275, "got expected epoch for 5.004");

done_testing;
