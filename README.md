# smoke-me-smoker.pl

This is a script to run Test::Smoke's `smokecurrent.sh` on a priority
selected set of branches, by default:

- `blead` - the main development branch (high activity)
- `maint-5.\d\d` - the maintenance branches for older release
- `smoke-me/...` - topic branches pushed by committers

Done in that priority order.

By default only one configuration is built:

- `default` - uses the default `smokecurrent.buildcfg`

## Installation

First install [Test::Smoke](https://metacpan.org/dist/Test-Smoke), and configure it:

```
$ cd .../smoke
$ perl tsconfigsmoke.pl
```

Set the sync_type to `git`, the default;

```
-- Sync section --
** sync_type - The source tree sync method.

How would you like to sync the perl-source?
<git|copy|hardlink|snapshot> [git] $ 
Got [git]
```

Set `gitbare` to true:

```
** gitbare - Clone as a bare repository

Clone bare git repository?
<y|N> [n] $ y
Got [y]
```

Don't change `gitbranchfile`:

```
** gitbranchfile - The name of the file where the gitbranch is stored.

File name to put branch name for smoking in?
[smokecurrent.gitbranch] $ 
Got [smokecurrent.gitbranch]
Got [/home/perlsmoker/smoke/smokecurrent.gitbranch]
  >> Created '/home/perlsmoker/smoke/smokecurrent.gitbranch'
```

Don't schedule smokes (`docron`):
```
* docron - I see you have '/usr/bin/crontab'


Should the smoke be scheduled?
<N|y> [Y] $ n
Got [n]
```

If you are smoking multiple configurations, disable `smartsmoke`:
```
** smartsmoke - Do not smoke when the source-tree did not change.

Skip smoke unless patchlevel changed?
<Y|n> [y] $ n
Got [n]
```

If you are using the `default` build configuration, this use the
default build configuration file that the Test::Smoke installer
creates, so don't change that step:

```
** cfg - The name of the BuildCFG file.

Which build configurations file would you like to use?
[/home/perlsmoker/smoke/smokecurrent.buildcfg] $ 
Got [/home/perlsmoker/smoke/smokecurrent.buildcfg]
Got [/home/perlsmoker/smoke/smokecurrent.buildcfg]
We removed/added some Configure options.
Some options that do not apply to your platform were found.
(Comment-lines left out below, but will be written to disk.)
...
```

You can edit `smokecurrent.buildcfg` as desired.

If you don't choose to send reports for the mailing list you may want
to add a `from` key to `smokecurrent_config` with your email address
(or something identifiable) so the source of your smokes can be
identified for follow-up.

One you've done this, run a sync:

```
$ cd .../smoke
$ perl tssynctree.pl -c smokecurrent_config
```

Now fetch `smoke-me-smoker.pl`, this should be under the same base
directory as the `Test::Smoke` `smoke` directory:

```
$ git clone https://github.com/tonycoz/smoke-me.git
$ cd smoke-me
```

If this is new, create a "seen" database:

```
$ touch ../seen.txt
```

and create a configuration file:

```
echo "{\"base\":\"$(realpath ..)/\"}" >smoke-me.cfg
```

Test the configuration:
```
$ perl smoke-me-smoker.pl -vv run -c1
```

which will error if there's a configuration problem, if the
configuration is good it will print a summary of the job selection
rules, select and job skip running it, something like:

```
$ perl smoke-me-smoker.pl -vv run -c1
Grouped rules
  Group priority 10
    blead  default
  Group priority 20
    (?^u:maint-\d\.\d\d)  default
  Group priority 30
    (?^u:smoke-me/[a-zA-Z0-9/_+.-]+)  default
Scanning
Found job:
   branch: blead (1de0457d57c047e26bd1254ebfbd4c2284bb6045)
   config: default (smokecurrent.buildcfg)
Building configuration file /tmp/_tF1CMe6cQ with config /home/perlsmoker/smoke/smokecurrent.buildcfg
Selecting branch blead
Invoking /home/perlsmoker//smoke/smokecurrent.sh with CFGNAME=/tmp/_tF1CMe6cQ
Running /home/perlsmoker//smoke/smokecurrent.sh
  (invocation disabled)
```

To run a single job:

```
$ perl smoke-me-smoker.pl -a run -c1
```

To run jobs forever:

```
$ perl smoke-me-smoker.pl -a run
```
