package PerlSmokeMe::TestUtil;
use v5.36;
use File::Temp "tempdir";
use Exporter qw(import);
use JSON;

our @EXPORT_OK = qw(cfg_dir try_cfg);

my $dir;

sub cfg_dir {
    unless ($dir) {
        $dir = tempdir;

        my $gitdir = "$dir/perl-from-github";
        mkdir $gitdir;
        system "git", "-C", $gitdir, "init";
        # trick git dir detection
        open my $fh, ">", "$gitdir/perl.h";
        close $fh;
        # trick smoke dir detection
        my $smdir = "$dir/smoke";
        mkdir $smdir;
        open $fh, ">", "$smdir/tssmokeperl.pl";
        close $fh;
        open $fh, ">", "$smdir/smokecurrent.buildcfg";
        close $fh;
        open $fh, ">", "$dir/seen.txt";
        close $fh;
    }

    $dir;
}

sub try_cfg ($hash) {
    $dir or cfg_dir();
    my $file = "$dir/test.cfg";
    open my $fh, ">", $file
        or die "Cannot create $file: $!";
    print $fh encode_json($hash);
    close $fh
        or die "Cannot cloe $file: $!";

    require PerlSmokeMe::Cfg;
    eval { PerlSmokeMe::Cfg->new($file) };
}

1;
