#!perl
use v5.36;
use PerlSmokeMe::Matcher;
use Test::More;
use lib 't/lib';
use PerlSmokeMe::TestUtil qw(cfg_dir try_cfg);

my $now = time;
my $cfg = try_cfg({ base => cfg_dir() })
    or die;

my $done = FakeDone->new;
my $blead = FakeBranch->new("blead", $now-3600);
my $maint542 = FakeBranch->new("maint-5.42", $now - 3600);
my $maint540 = FakeBranch->new("maint-5.40", $now - 3600);
my $random = FakeBranch->new("tonycoz/random", $now - 3600);
my $bad_blead = FakeBranch->new("tonycoz/blead", $now - 3600);
my $old = FakeBranch->new("smoke-me/old", $now - 32 * 86_400);
my $old_maint = FakeBranch->new("maint-5.36", $now - 32 * 86_400);
my $smokeme1 = FakeBranch->new("smoke-me/one", $now - 10 * 86_400);
my $smokeme2 = FakeBranch->new("smoke-me/two", $now - 10 * 86_400);

my @brules = $cfg->branch_rules;
my @crules = $cfg->config_rules;

my $matcher = PerlSmokeMe::Matcher->new($done, \@brules, \@crules);

{
    my @branches =
        (
         $blead,
         $maint542,
         $maint540,
         $old_maint,
        );
    my ($fbranch, $fconfig) = $matcher->match(\@branches);
    ok($fbranch, "found blead I hope");
    is($fbranch->name, "blead", "match blead");
    is($fconfig->{name}, "default", "expected config");
    $done->saw($fbranch->sha, $fconfig->{name});
    
    ($fbranch, $fconfig) = $matcher->match(\@branches);
    like($fbranch->name, qr/^maint-5\.4/, "should be a late maint branch");
    $done->saw($fbranch->sha, $fconfig->{name});
    ($fbranch, $fconfig) = $matcher->match(\@branches);
    like($fbranch->name, qr/^maint-5\.4/, "should be the other late maint branch");
    $done->saw($fbranch->sha, $fconfig->{name});
    ($fbranch, $fconfig) = $matcher->match(\@branches);
    is($fbranch, undef, "should be no match");

    push @branches, $old;
    ($fbranch, $fconfig) = $matcher->match(\@branches);
    is($fbranch, undef, "should be no match after adding old smoke-me");
    push @branches, $smokeme1;
    ($fbranch, $fconfig) = $matcher->match(\@branches);
    is($fbranch->name, "smoke-me/one", "should be smoke-me/one");
    $done->saw($fbranch->sha, $fconfig->{name});
    ($fbranch, $fconfig) = $matcher->match(\@branches);
    is($fbranch, undef, "should be no match");
    push @branches, $smokeme2;
    ($fbranch, $fconfig) = $matcher->match(\@branches);
    is($fbranch->name, "smoke-me/two", "should be smoke-me/two");
}

done_testing;

package FakeBranch {
    sub fake_sha {
        unpack "h*", pack "C*", map { rand 256 } 1..20
    }

    sub new ($class, $name, $epoch, $sha = fake_sha()) {
        my %hash =
            (
             name => $name,
             epoch => $epoch,
             sha => $sha,
            );
        bless \%hash, $class;
    }
    sub name ($self) { $self->{name} }
    sub epoch ($self) { $self->{epoch} }
    sub sha ($self) { $self->{sha} }
}

package FakeDone {
    sub new ($class) { bless {}, $class; }
    sub seen ($self, $sha, $cfg_name) { $self->{"$sha-$cfg_name"} }
    sub saw ($self, $sha, $cfg_name) {
        $self->{"$sha-$cfg_name"} = 1;
    }
}
