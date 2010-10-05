package PerlSmoker::Push;
use strict;
use LWP::UserAgent;
use Exporter qw(import);
use Digest::SHA qw(sha256_hex);
use Storable;

our @EXPORT_OK = qw(smoke_push smoke_push_queued status_push);

sub smoke_push {
  my %opts = @_;

  my $queue_dir = delete $opts{_queue};

  my $key = delete $opts{key};

  for my $f (qw/out rpt log/) {
    $opts{$f} = [ undef, $opts{$f}, Content => scalar(`cat $opts{$f}`) ];
  }
  $opts{when_at} = delete $opts{when};

  my $fn = time() . "." . int(rand(1000));

  store(\%opts, "$queue_dir/$fn")
    or die "Cannot save request to $queue_dir/$fn: $!";

  smoke_push_queued($queue_dir, $key);
}

sub smoke_push_queued {
  my ($queue_dir, $key) = @_;

  opendir my $dh, $queue_dir or die;
  my @files = grep -f "$queue_dir/$_", readdir $dh;
  closedir $dh;

  for my $file (@files) {
    my %work = %{retrieve("$queue_dir/$file")};
    $work{time} = time;

    $work{hash} = sha256_hex($key . $work{time});
    
    my $ua = LWP::UserAgent->new;
    my $resp = $ua->post
      (
       "http://perl.develop-help.com/cgi-bin/push.pl/push",
       Content_Type => "form-data",
       Content =>
       [
	%work
       ],
      );
    
    $resp->is_success
      or die $resp->status_line;
    
    my $content = $resp->decoded_content;
    $content =~ tr/\r//d;
    my ($result, $msg) = split /\n/, $content;
    $result eq "DONE"
      or die($msg || "no error message");

    unlink "$queue_dir/$file";
  }
}

sub status_push {
  my %opts = @_;

  $opts{time} = time;
  my $key = delete $opts{key};

  $opts{hash} = sha256_hex($key . $opts{time});

  my $ua = LWP::UserAgent->new;
  my $resp = $ua->post
    (
     "http://perl.develop-help.com/cgi-bin/push.pl/status",
     Content_Type => "form-data",
     Content =>
     [
      %opts
     ],
    );

  $resp->is_success
    or die $resp->status_line;

  my $content = $resp->decoded_content;
  $content =~ tr/\r//d;
  my ($result, $msg) = split /\n/, $content;
  $result eq "DONE"
    or die($msg || "no error message");
}

1;
