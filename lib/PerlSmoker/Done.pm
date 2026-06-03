package PerlSmoker::Done;
use v5.36;

sub new ($class, $filename, $maxage = 365) {
    my $workfile = "$filename.wrk";
    -f $filename
        or die "No such file $filename, touch it for a fresh start";
    my $self = bless {
        filename => $filename,
        workfile => $workfile,
        maxage => $maxage
    }, $class;
    $self->_load;
    $self;
}

sub _load ($self) {
    open my $fh, "<", $self->{filename}
      or die "Cannot open $self->{filename}: $!";
    my @lines = <$fh>;
    chomp @lines;
    my %seen;
    for my $line (@lines) {
      my ($what, $when) = split ' ', $line;
      $what =~ m(^[0-9a-f]{32}-[a-zA-Z0-9/_+.-]+$)
        or die "Invalid run $what found in seen file\n";
      $when =~ /^[1-9][0-9]+$/
        or die "Invalid epoch $when found in seen file\n";
      $seen{$what} = $when;
    }
    $self->{_seen} = \%seen;
    $self->_age;
}

sub seen ($self, $sha, $config_name) {
    $self->{seen}{"$sha-$config_name"};
}

sub saw ($self, $sha, $config_name) {
    $self->{seen}{"$sha-$config_name"} = time;
    $self->_update;
}

sub _age ($self) {
    my $seen = $self->{_seen};
    my $oldest = time() - $self->{maxage};
    my @release = grep { $seen->{$_} < $oldest } keys %$seen;
    delete $seen->@{@release};
}

sub _update ($self) {
    $self->_age;
    my $seen = $self->{_seen};

    open my $fh, ">", $self->{workfile}
      or die "Cannot create $self->{workfile}: $!";
    print $fh "$_ $seen->{$_}\n" for sort keys %$seen;
    close $fh
        or die "Cannot close $self->{workfile}: $!";
    rename $self->{workfile}, $self->{filename}
        or die "Cannot rename $self->{workfile} to $self->{filename}: $!";
}

1;

=head1 NAME

PerlSmoker::Done - a simple database of processed shas and configs

=head1 SYNOPSIS

  use PerlSmoker::Done;
  my $done = PerlSmoker::Done->new($filename, $maxage_secs);
  if (!$done->seen($sha, $config_name)) {
     # process this sha with config
     $done->saw($sha, $config_name);
  }

=head1 DESCRIPTION

A simple database of SHAs and the configurations processed for those
shas.

=cut
