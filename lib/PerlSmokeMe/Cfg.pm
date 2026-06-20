package PerlSmokeMe::Cfg;
use v5.36;
use FindBin;
use Scalar::Util qw(looks_like_number reftype);

sub new ($class, $cfg_file) {
    my $cfg = MyCfg->new($cfg_file);

    my $base = $cfg->get("base") // "$FindBin::Bin/..";
    # git checkout to update and search for branches
    my $gitbase = $cfg->get("gitbase") || "$base/perl-from-github";
    -d $gitbase && -f "$gitbase/config" && -d "$gitbase/refs"
        or die "$cfg_file: gitbase '$gitbase' isn't a bare git clone of perl\n";
    # where to find the Test-Smoke installation
    my $smoke = $cfg->get("smoke") // "$base/smoke";
    -d $smoke && -f "$smoke/tssmokeperl.pl"
        or die "$cfg_file: smoke '$smoke' not a Test::Smoke install\n";
    -f "$smoke/smokecurrent.lck"
        and die "$cfg_file: smoke directory '$smoke' has lock file\n";
    my $seen_file = $cfg->get("seen") // "$base/seen.txt";
    -f $seen_file
        or die <<~ERROR;
            $cfg_file: seen '$seen_file' not a file
            If this is a new install, then `touch $seen_file`.
            ERROR
    my $seen_age = $cfg->get("seen_age") // 86_400 * 365;
    looks_like_number($seen_age)
        or die "$cfg_file: seen_age '$seen_age' must be a number\n";
    my $cfg_branch_rules = $cfg->get("branches") // {};
    ref $cfg_branch_rules && reftype($cfg_branch_rules) eq "HASH"
        or die "$cfg_file: branches must be a hash\n";
    my %branch_rules =
        (
         blead =>
         {
             name => "blead",
             priority => 10,
         },
         maint =>
         {
             name => qr(maint-\d\.\d\d),
             priority => 20,
         },
         "smoke-me" =>
         {
             name => qr(smoke-me/[a-zA-Z0-9/_+.-]+),
             priority => 30,
         },
        );
    for my $key (keys %$cfg_branch_rules) {
        my $cfg_rule = $cfg_branch_rules->{$key};
        my $rule = $branch_rules{$key};
        if ($rule) {
            $rule->@{keys %$cfg_rule} = values %$cfg_rule;
        }
        else {
            $branch_rules{$key} = $cfg_rule;
        }
    }
    # allows config to delete default rules
    # preserve the rule keys for reporting
    for my $branch_key (keys %branch_rules) {
        ref($branch_rules{$branch_key})
            or die "$cfg_file: branch{$branch_key} must be a hash\n";
        $branch_rules{$branch_key}{key} = $branch_key;
    }
    my @branch_rules = sort { $a->{key} cmp $b->{key} }
        grep { $_->{name} } values %branch_rules;
    for my $branch_rule (@branch_rules) {
        # JSON doesn't do regexp objects, so treat "qr/.../" as a regexp
        my $err_prefix = "$cfg_file: branches{$branch_rule->{key}}";
        if ($branch_rule->{name} =~ m(^qr/(.*)/$)) {
            my $qr = eval { qr/$1/; };
            $qr or die "$err_prefix: Failed to compile regexp /$1/:\n$@\n";
            $branch_rule->{name} = $qr;
        }
        looks_like_number($branch_rule->{priority})
            or die "$err_prefix: priority must be numeric\n";
    }

    my $cfg_config_rules = $cfg->get("configs") // {};
    ref $cfg_config_rules && reftype($cfg_config_rules) eq "HASH"
        or die "$cfg_file: configs must be a hash\n";
    my %config_rules =
        (
         default =>
         {
             name => "default",
             priority => 0,
             file => "smokecurrent.buildcfg",
         },
        );
    for my $key (keys %$cfg_config_rules) {
        my $cfg_rule = $cfg_config_rules->{$key};
        my $rule = $config_rules{$key};
        if ($rule) {
            $rule->@{keys %$cfg_rule} = values %$cfg_rule;
        }
        else {
            $config_rules{$key} = $cfg_rule;
        }
    }
    for my $config_key (keys %config_rules) {
        $config_rules{$config_key}{key} = $config_key;
    }
    my @config_rules = sort { $a->{name} cmp $b->{name} }
        grep { $_->{name} } values %config_rules;
    for my $config_rule (@config_rules) {
        my $err_prefix = "$cfg_file: configs{$config_rule->{key}}";
        ref($config_rule->{name})
            and die "$err_prefix: name must be a string\n";
        looks_like_number($config_rule->{priority})
            or die "$err_prefix: priority must be numeric\n";
        ref($config_rule->{file})
            and die "$err_prefix: file must be a string\n";
        my $full_cfg = File::Spec->rel2abs($config_rule->{file}, $smoke);
        -f $full_cfg
            or die "$err_prefix: file $full_cfg isn't a file\n";
    }

    my $gitfetchopts = $cfg->get("gitfetchopts") // [ '-p' ];
    reftype $gitfetchopts eq "ARRAY"
        or die "$cfg_file: gitfetchopts must be an array reference\n";

    bless
    {
        base => $base,
        gitbase => $gitbase,
        smoke => $smoke,
        seen => $seen_file,
        seen_age => $seen_age,
        branches => \@branch_rules,
        configs => \@config_rules,
        gitfetchopts => $gitfetchopts,
    }, $class;
}

sub gitbase ($self) {
    $self->{gitbase};
}

sub smoke ($self) {
    $self->{smoke};
}

sub seen ($self) {
    $self->{seen};
}

sub seen_age ($self) {
    $self->{seen_age};
}

sub gitfetchopts ($self) {
    wantarray or die "gitfetchopts must be called in list context";
    $self->{gitfetchopts}->@*;
}

sub branch_rules ($self) {
    wantarray or die "branch_rules must be called in list context";
    $self->{branches}->@*;
}

sub config_rules ($self) {
    wantarray or die "config_rules must be called in list context";
    $self->{configs}->@*;
}

package MyCfg;
use Cpanel::JSON::XS;

sub new ($class, $file) {
    open my $fh, "<", $file
        or die "Cannot open $file: $!";
    my $raw = do { local $/; <$fh> };
    my $data = Cpanel::JSON::XS::decode_json($raw);
    bless $data, $class;
}

sub get ($self, $key) {
    $self->{$key};
}

1;
