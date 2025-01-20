use strict;
use warnings;
use Test::More;
use FindBin '$Bin';

local @ARGV = 'dummy';
my $cpanspec = "$Bin/../cpanspec";
require $cpanspec;

my %config;
my $spec;

my $label = "no patches";
$spec = main::process_patches(\%config);
is $spec->{autosetup_args}, '-p1', "$label (autosetup)";
is scalar @{ $spec->{sources} }, 0, "$label (sources)";
is_deeply $spec->{patches}, [], "$label (patches)";

$label = "undef";
$config{patches} = {
    'foo.patch' => undef,
};
$spec = main::process_patches(\%config);
is $spec->{autosetup_args}, '-N', "$label (autosetup)";
like $spec->{sources}->[0], qr{Patch0:.*foo.patch}, "$label (sources)";
is_deeply $spec->{patches}, ['%patch -P0'], "$label (patches)";

$label = "-p0";
$config{patches} = {
    'foo.patch' => '-p0',
};
$spec = main::process_patches(\%config);
is $spec->{autosetup_args}, '-N', "$label (autosetup)";
like $spec->{sources}->[0], qr{Patch0:.*foo.patch}, "$label (sources)";
is_deeply $spec->{patches}, ['%patch -P0 -p0'], "$label (patches)";

$label = "-p1";
$config{patches} = {
    'foo.patch' => '-p1',
};
$spec = main::process_patches(\%config);
is $spec->{autosetup_args}, '-p1', "$label (autosetup)";
like $spec->{sources}->[0], qr{Patch0:.*foo.patch}, "$label (sources)";
is_deeply $spec->{patches}, [], "$label (patches)";

$label = "-p0, -p1 and undef";
$config{patches} = {
    'foo.patch' => '-p1',
    'bar.patch' => '-p0',
    'boo.patch' => undef,
};
$spec = main::process_patches(\%config);
is $spec->{autosetup_args}, '-N', "$label (autosetup)";
like $spec->{sources}->[0], qr{Patch0:.*bar.patch}, "$label (source 0)";
like $spec->{sources}->[1], qr{Patch1:.*boo.patch}, "$label (source 1)";
like $spec->{sources}->[2], qr{Patch2:.*foo.patch}, "$label (source 2)";
is_deeply $spec->{patches}, ['%patch -P0 -p0', '%patch -P1', '%patch -P2 -p1'], "$label (patches)";

$label = "-p1 with ref";
$config{patches} = {
    'foo.patch' => '-p1 PATCH-FIX-UPSTREAM url',
};
$spec = main::process_patches(\%config);
is $spec->{autosetup_args}, '-p1', "$label (autosetup)";
like $spec->{sources}->[0], qr{\# PATCH-FIX-UPSTREAM url}, "$label (sources)";
like $spec->{sources}->[1], qr{Patch0:.*foo.patch}, "$label (sources)";
is_deeply $spec->{patches}, [], "$label (patches)";

done_testing;

