#!/usr/bin/perl
use strict;
use warnings;
use 5.010;
use Data::Dumper;
use Getopt::Long;

GetOptions(
    "debug" => \my $debug,
    "dry" => \my $dry,
    "help|h" => \my $help,
)   # flag
or die "Error in command line arguments";

if ($help) {
    print <<'EOM';
Usage:
    batch.pl /path/to/packages 0 50 # process the first 51 packages
EOM
    exit;
}

my ($dir, $from, $to) = @ARGV;
$from ||= 0;
$to ||= $from;

my @skip = qw/
    perl-AcePerl
    perl-Acme-MetaSyntactic
    perl-Acme-Ook
    perl-Algorithm-Munkres
    perl-Alien-LibGumbo
    perl-Alien-SVN
    perl-Alien-Tidyp
    perl-Apache-AuthNetLDAP
    perl-Apache-Filter
    perl-Apache-SessionX
    perl-Apache-Gallery
    perl-App-ProcIops
    perl-App-Nopaste
    perl-App-SVN-Bisect
    perl-App-gcal
    perl-Array-Dissect
    perl-Audio-CD
    perl-Authen-SASL-Cyrus
    perl-BIND-Conf_Parser
    perl-BSXML
    perl-Boost-Geometry-Utils
    perl-Class-Accessor-Chained
    Class-Multimethods
    perl-Crypt-HSXKPasswd
    perl-Crypt-Rot13
/;
my %skip;
@skip{ @skip } = ();

opendir my $dh, $dir or die $!;
my @pkgs = sort grep {
    -d "$dir/$_" && m/^perl-/
    and not exists $skip{ $_ }
} readdir $dh;
closedir $dh;

my $count = @pkgs;
say "Total: $count";

my $opt_debug = $debug ? '--debug' : '';
for my $i ($from .. $to) {
    my $pkg = $pkgs[ $i ];
    chdir $dir;
    say "=========== ($i) $pkg";
    next if $dry;
    chdir $pkg;
    my $mod = $pkg;
    $mod =~ s/^perl-//;
    my @glob = glob("$mod*");
    my $cmd = qq{cpanspec $opt_debug -v -f --skip-changes --pkgdetails /tmp/02packages.details.txt.gz @glob 2>&1};
    say "Cmd: $cmd";
    my $out = qx{$cmd};
    say $out;

}
