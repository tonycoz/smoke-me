package PerlSmokeMe::Invoker;
use v5.36;
use File::Temp ();
use Data::Dumper;

sub new ($class, $cfg) {
    my $self = bless {
        cfg => $cfg,
        real => 0,
    }, $class;
    $self->_load_config;
    $self;
}

sub set_real($self, $real) {
    $self->{real} = $real;
}

sub _load_config ($self) {
    my $smoke = $self->{cfg}->smoke;
    my $source_file = "$smoke/smokecurrent_config";
    open my $fh, "<", $source_file
        or die "Cannot open $source_file: $!";
    my $source = do { local $/; <$fh> };
    close $fh;
    my $conf;
    eval $source
        or die "Cannot evaluate $source_file: $@";
    $self->{orig_config} = $conf;

    $self->{smokecurrent} = "$smoke/smokecurrent.sh";
    $self->{branchname} = "$smoke/smokecurrent.gitbranch";
}

sub invoke ($self, $branch_name, $build_cfg) {
    defined $branch_name
        or die "invoke: branch_name not defined";
    defined $build_cfg
        or die "invoke: build_cfg not defined";
    # select the correct buildcfg file
    my $cfg_fh = File::Temp->new;
    my $cfg_name = $cfg_fh->filename;
    my %cfg = $self->{orig_config}->%*;

    my $build_file = File::Spec->rel2abs($build_cfg->{file}, $self->{cfg}->smoke);

    print "Building configuration file $cfg_name with config $build_file\n";
    $cfg{cfg} = $build_file;
    print $cfg_fh Data::Dumper->Dump([\%cfg], [ 'conf' ]), ";\n";
    close $cfg_fh
        or die "Cannot close temp config file: $!";

    print "Selecting branch $branch_name\n";
    # select the branch
    open my $bfh, ">", $self->{branchname}
        or die "Cannot create $self->{branchname}: $!";
    print $bfh $branch_name;
    close $bfh
        or die "Cannot close $self->{branchname}: $!";

    print "Invoking $self->{smokecurrent} with CFGNAME=$cfg_name\n";
    local $ENV{CFGNAME} = $cfg_name;
    $self->_run($self->{smokecurrent});
}

sub _run ($self, @cmd) {
    print "Running @cmd\n";
    if ($self->{real}) {
        return system @cmd;
    }
    else {
        print "  (invocation disabled)\n";
        sleep 5;
        return 0;
    }
}

1;
