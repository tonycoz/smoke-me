#!perl
use v5.36;
use PerlSmokeMe::Cfg;
use Test::More;
use lib 't/lib';
use PerlSmokeMe::TestUtil qw(try_cfg cfg_dir);

my $dir = cfg_dir();

{
    my $cfg = try_cfg({ base => $dir });
    ok($cfg, "simple, valid") or die $@;
    is_deeply([ $cfg->branch_rules ],
              [
               {
                   key => "blead",
                   name => "blead",
                   priority => 1,
               },
               {
                   key => "maint",
                   name => qr/maint-\d\.\d\d/,
                   priority => 2,
               },
               {
                   key => "smoke-me",
                   name => qr(smoke-me/[a-zA-Z0-9/_+.-]+),
                   priority => 3,
               },
              ], "check default branches");
    is_deeply([ $cfg->config_rules ],
              [
               {
                   key => "default",
                   name => "default",
                   priority => 0,
                   file => "smokecurrent.buildcfg",
               },
              ], "check default configs");
    is($cfg->gitbase, "$dir/perl-from-github", "gitbase");
    is($cfg->smoke, "$dir/smoke", "smoke");
    is($cfg->seen, "$dir/seen.txt", "seen");
    is($cfg->seen_age, 365 * 86_400, "seen_age");
    is($cfg->gitfetchopts, "-p", "gitfetchopts");
}
{
    my $cfg = try_cfg({ base => $dir, branches => [] });
    ok(!$cfg, "fail config with branches array");
    like($@, qr/branches must be a hash/, "check error");
}
{
    my $cfg = try_cfg({ base => $dir, configs => [] });
    ok(!$cfg, "fail config with configs array");
    like($@, qr/configs must be a hash/, "check error");
}
{
    my $cfg = try_cfg({ base => $dir, smoke => "$dir/unknown" });
    ok(!$cfg, "fail config with bad smoke directory");
    like($@, qr/not a Test::Smoke install/, "check error");
}
{
    my $cfg = try_cfg({ base => $dir, seen => "$dir/unseen.txt" });
    ok(!$cfg, "fail config with bad seen filename");
    like($@, qr/seen '.*' not a file/, "check error");
}
{
    my $cfg = try_cfg({ base => $dir, seen_age => "bad" });
    ok(!$cfg, "fail config with bad seen_age");
    like($@, qr/seen_age '.*' must be a number/, "check error");
}


done_testing;

