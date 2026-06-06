package PerlSmokeMe::Git;
use v5.36;

sub new ($class, %opts) {
    $opts{upstream} ||= "origin";
    $opts{dir} or die "No git directory";
    -d $opts{dir} or die "$opts{dir} not a directory";

    bless \%opts, $class;
}

sub branches ($self) {
    my @branches = $self->_git("branch", "-r");
    chomp @branches;
    @branches = grep m( +(?:remotes/)?\Q$self->{upstream}\E/), @branches;
    s(^ +(?:remotes/)?\Q$self->{upstream}\E/)() for @branches;
    return map {
        PerlSmokeMe::Git::Branch->new($self, $_)
    }
    grep {
        !/^HEAD /
    } @branches;
}

sub fetch ($self, @opts) {
    $self->_git("fetch", @opts);
    1;
}

sub _git($self, @cmd) {
    unshift @cmd, "git", "-C", $self->{dir};
    #local $ENV{GIT_WORK_TREE} = $self->{dir};
    open my $gitfh, "-|", @cmd
        or die "Cannot run @cmd: $!";
    my @out = <$gitfh>;
    unless (close $gitfh) {
        die "Command [@cmd] failed: $?";
    }
    @out;
}

package PerlSmokeMe::Git::Branch;

sub new ($class, $git, $name) {
    bless {
        git => $git,
        name => $name,
    }, $class;
}

sub name ($self) {
    $self->{name};
}

sub epoch ($self) {
    $self->_info->{epoch};
}

sub sha ($self) {
    $self->_info->{sha};
}

sub _info ($self) {
    unless ($self->{_info}) {
        my ($line) = $self->{git}
          ->_git("log", "-n1", '--pretty=%H %ct',
                 "$self->{git}{upstream}/$self->{name}");
        $line or die "Cannot load info for $self->{name}";
        chomp $line;
        my @fields = split ' ', $line;
        my %info;
        @info{qw(sha epoch)} = @fields;
        $self->{_info} = \%info;
    }
    $self->{_info};
}

1;
