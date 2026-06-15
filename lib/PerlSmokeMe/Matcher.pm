package PerlSmokeMe::Matcher;
use v5.36;
use strict;

sub new ($class, $done, $branch_rules, $config_rules) {
    $branch_rules = [ sort { $a->{priority} <=> $b->{priority} } @$branch_rules ];
    $config_rules = [ sort { $a->{priority} <=> $b->{priority} } @$config_rules ];
                      
    bless {
        done => $done,
        brules => $branch_rules,
        crules => $config_rules,
    }, $class;
}

sub match ($self, $branches) {
    # we only test branches updated in the last 30 days
    my $earliest = time() - 30 * 86_400;
    my $done = $self->{done};
    for my $brule ($self->{brules}->@*) {
        my @mbranches;
        my $name = $brule->{name};
        if (ref $name) {
            my $re = qr/^$name$/;
            @mbranches = grep $_->name =~ $re, @$branches;
        }
        else {
            @mbranches = grep $_->name eq $name, @$branches;
        }
        @mbranches = grep $_->epoch > $earliest, @mbranches;
        for my $crule ($self->{crules}->@*) {
            my @cand = grep !$done->seen($_->sha, $crule->{name}),
                @mbranches;
            if (@cand) {
                return ( $cand[rand @cand], $crule );
            }
        }
    }
    return;
}

1;

=head1 NAME

PerlSmokeMe::Matcher - match branches against branch and config rules.

=head1 SYNOPSIS

  use PerlSmokeMe::Done;
  use PerlSmokeMe::Matches;
  use PerlSmokeMe::Git;

  my $done = PerlSmokeMe::Done->new($filename);
  my $git = PerlSmokeMe::Git->new($gitdir);
  my $matcher = PerlSmokeMe::Matcher->new($done, \@branch_rules, \@config_rules);
  my @branches = $git->branches;
  my ($branch_object, $config_entry) = $matcher->match(\@branches);

=head1 DESCRIPTION

Given a list of branches select a branch to test based on the
configured branch and test configuration rules.

Each branch rule is a hash:

  my %rule =
    (
     name => "name" | qr/regexp/,
     priority => $some_priority
    );

C<name> can be a literal name, such as "blead", or a regexp matched
against a branch name, like C<qr/smoke-me\/.*/>.

=cut
