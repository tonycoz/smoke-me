#!perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use PerlSmokeMe::App;

PerlSmokeMe::App->run(\@ARGV);

=head1 NAME

smoke-me-smoker.pl - run build smoke tests continuously

=head1 SYNOPSIS

  # select a branch and config and don't actually run it
  # (for checking configuration)
  perl smoke-me-smoker.pl run -c1

  # live, run smokes forever
  perl smoke-me-smoker.pl -a run

=head1 DESCRIPTION

Based on the configuration, this runs Test::Smoke runs on the the git
tree, selecting a branch and build configuration file based on the
configured rules.

This expects a specific layout, most of which is setup by the
Test::Smoke install and its configuration.

When configuring Test::Smoke you need to ensure:

=over

=item *

"The source tree sync method" - must be "git".

=item *

"Clone bare git repository?" - must be Y (needed to propagate remote
branches through to the build tree.)

=item *

"Skip smoke unless patchlevel changed?" - should be N if your are
smoking multiple configurations.

=back

You will need to run a single smoke with F<smokecurrent.sh> to
populate the git trees.

You may want to manually populate the "from" key in
F<smokecurrent_config> to get an email address passed through to the
report.

=over

=item *

F<base/seen.txt> - a text file tracking the builds that have been run.
This should be created as an empty file during setup (eg. with C<touch
seen.txt>).

=item *

F<base/perl-from-github/> - a bare git checkout of the perl repository.
Created by Test::Smoke.

=item *

F<base/smoke/> - the Test::Smoke installation.

=item *

F<base/perl-current/> - the git checkout used to actually run the
smoke tests.  Created by Test::Smoke.

=item *

F<base/smoke-me/> - this software.

=item *

F<base/smoke-me/smoke-me.cfg> - a JSON file with any configuration.
This can be just C<{"base":"your base directory"}> if you use the
described layout.

=back

=head1 OPTIONS

The base options are:

=over

=item C<-a> - makes the operations active.  Otherwise changes to the
seen database are not saved and the smokes are not invoked.  The idea
is to test your configuration with no C<-a> then add C<-a> for live
use.

=item C<-c filename> - specify the configuration filename.  This
defaults to F<smoke-me.cfg> in the same directory as
F<smoke-me-smoker.pl>.

=item C<-v> - increase verbosity

=back

Following the base options is a command, currently only:

=over

=item C<run>

Starts running smokes.  Takes one option:

C<-c count> - the number of smokes to run.  By default this is zero
which means to run forever.

=back

=head1 What is tested?

The default configuration is to test the following branches, if
they've been updated in the last 30 days:

=over

=item *

C<blead> - the main development branch

=item *

C<maint-5.xx> - the maint perl branches

=item *

C<smoke-me/*> - the topic branches proposed for smoke testing.  Note
that the configuration limits the possible names to avoid shell
metacharacters and Unicode since I don't want to deal with either, see
the details below.

=back

By default the selected branch is run with the C<default>
configuration which uses the Test::Smoke installed
C<smokecurrent.buildcfg> file, which you can adapt as you wish.

=head1 Configuring what is run.

Branches and configurations are selected in priority order, so by
default blead is selected if it has an untested configuration, then
maint, then smoke-me.

Branch rule/configuration rules are selected in sum of branch rule and
configuration rule priority, lowest priority first.

If multiple branch/configuration rules have the same priority sum they are
selected from randomly.

The branches to run are specified by the C<branches> key in
F<smoke-me.cfg>, with the default specified as if by:

   {
     "blead":
         {
             "name": "blead",
             "priority": 10
         },
     "maint":
         {
             "name": "qr/maint-\d\.\d\d/",
             "priority": 20
         },
     "smoke-me":
         {
             "name": "qr/smoke-me/[a-zA-Z0-9/_+.-]+/",
             "priority": 30
         },
   }

Since JSON doesn't support qr// it is emulated, if the name starts
with C<qr/> and ends with C</> those are removed and the remains are
compiled as a qr// object.  No other escaping is done.

If the C<name> is a regular expression it is matched against the full
branch name, ie as if C</^$yourre$/>.

The priority order for equal priorities is unspecified.

You can respecify a key to replace members of that key.  For example
if you set:

   "branches":{
      "maint":{ "name": "" }
   }

in F<smoke-me.cfg> then the maint-5.xx branches are not tested, since
entries with no C<name> are removed.

Or add more branches:

   "branches":
   {
     "my-branches":
     {
        "name":"qr/my-branches/.*/",
        "priority": 40
     }
   }

Change the priority of the "maint" rule:

   "branches":{
      "maint":{ "priority": 10 }
   }

The configurations to run are specified similarly, the defauilt is:

   "configs":
    {
       "default":
         {
             "name": "default",
             "priority": 0,
             "file": "smokecurrent.buildcfg"
         }
    }

You can add extra configurations by adding extra keys:

    "configs":
      {
        "asan":
          {
             "name":"asan",
             "priority":1,
             "file":"smokecurrent.buildasan"
          }
      }

or replace the C<default> configuration, similar to the way you do for
branches.  Note the key is used simply for configuration replacement
and doesn't need to match the configuration C<name> field.

=cut
