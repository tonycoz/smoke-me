package PerlSmokeMe::Matcher;
use v5.36;
use strict;
use List::Util qw(shuffle);

sub new ($class, $done, $branch_rules, $config_rules, $verbose=0) {
    $branch_rules = [ sort { $a->{priority} <=> $b->{priority} } @$branch_rules ];
    $config_rules = [ sort { $a->{priority} <=> $b->{priority} } @$config_rules ];

    # group by sum of priorities
    my %grouped;
    for my $brule (@$branch_rules) {
        for my $crule (@$config_rules) {
            my $priority = $brule->{priority} + $crule->{priority};
            push $grouped{$priority}->@*, [ $brule, $crule, $priority ];
        }
    }
    my @grouped = @grouped{ sort { $a <=> $b } keys %grouped };
    if ($verbose >= 2) {
        print "Grouped rules\n";
        for my $group (@grouped) {
            print "  Group priority $group->[0][2]\n";
            for my $entry (@$group) {
                print "    $entry->[0]{name}  $entry->[1]{name}\n";
            }
        }
    }
                      
    bless {
        done => $done,
        brules => $branch_rules,
        crules => $config_rules,
        grouped => \@grouped,
        verbose => $verbose,
    }, $class;
}

sub _match_branch ($branches, $name) {
    if (ref $name) {
        my $re = qr/^$name$/;
        return grep $_->name =~ $re, @$branches;
    }
    else {
        return grep $_->name eq $name, @$branches;
    }
}

sub match ($self, $branches) {
    # we only test branches updated in the last 30 days
    my $earliest = time() - 30 * 86_400;
    my $done = $self->{done};
    my $verbose = $self->{verbose};

    print "Scanning\n" if $verbose;
    for my $group ($self->{grouped}->@*) {
        my @options = shuffle @$group;
        for my $option (@options) {
            my ($brule, $crule, $priority) = @$option;
            my @mbranches =
                grep { $_->epoch > $earliest }
                _match_branch($branches, $brule->{name});
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
  my $matcher = PerlSmokeMe::Matcher->new($done, \@branch_rules, \@config_rules, $verbose);
  my @branches = $git->branches;
  my ($branch_object, $config_rule) = $matcher->match(\@branches);

=head1 DESCRIPTION

Given a list of branches select a branch to test based on the
configured branch and test configuration rules.

Each branch rule is a hash:

  my %branch_rule =
    (
     name => "name" | qr/regexp/,
     priority => $some_priority
    );

C<name> can be a literal name, such as "blead", or a regexp matched
against a branch name, like C<qr/smoke-me\/.*/>.

Each config rule is a similar hash:

  my %config_rule =
    (
     name => "name",
     priority => $some_priority,
     file => "smokecurrent.build.cfg", # some build cfg filename
    );

=cut
