package PerlSmoker::Push;
use strict;
use LWP::UserAgent;
use Exporter qw(import);
use Digest::SHA qw(sha256_hex);

our @EXPORT_OK = qw(smoke_push);

sub smoke_push {
  my %opts = @_;

  for my $f (qw/out rpt log/) {
    $opts{$f} = [ $opts{$f} ];
  }
  $opts{when_at} = delete $opts{when};

  $opts{time} = time;
  my $key = delete $opts{key};

  $opts{hash} = sha256_hex($key . $opts{time});

  my $ua = LWP::UserAgent->new;
  my $resp = $ua->post
    (
     "http://perl.develop-help.com/cgi-bin/push.pl/push",
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
