#!perl
use v5.36;
use PerlSmoker::Done;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;

my $sha1 = "e33873a090fb0dcd67df9a41ec9ff90c11749d01";
my $sha2 = "59cf203f810b52d40552961e7fbb1cab9cdde22a";
my $sha3 = "e30afae0a3edd83821767f6ac56dbf053c52f468";

my $temp_dir = tempdir();

my $seen_file = File::Spec->catfile($temp_dir, "seen.dat");

{
    my $done;
    ok(!eval { $done = PerlSmoker::Done->new($seen_file); 1 },
       "fail to create file from scratch");
    like($@, qr/touch/, "error mentions 'touch'");
}

{
    my $old = time() - 366 * 86400;
    my $now = time();
    open my $fh, ">", $seen_file
        or die "Cannot create $seen_file: $!";
    print $fh <<EOS;
$sha1-default $old
$sha1-other $old
$sha2-default $now
EOS
    close $fh
        or die "Cannot close $seen_file: $!";
    my $done = PerlSmoker::Done->new($seen_file);
    ok(!$done->seen($sha1, "default"), "don't have aged out entry");
    ok(!$done->seen($sha1, "other"), "or the other old entry");
    ok($done->seen($sha2, "default"), "do have the new entry");
    $done->saw($sha3, "default");
    ok($done->seen($sha3, "default"), "see the entry we just added");
    undef $done;

    $done = PerlSmoker::Done->new($seen_file);
    ok($done->seen($sha3, "default"), "still see the entry");
}

done_testing();
