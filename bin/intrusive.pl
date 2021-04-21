#!/usr/bin/perl
use strict;
use warnings;
use 5.010;
use JSON::PP;
use File::Basename qw/ dirname /;
my $bin = dirname(__FILE__);
require "$bin/../lib/Intrusive.pm";

my $coder = JSON::PP->new->utf8->pretty->canonical;

my ($path) = @ARGV;

my $deps = Intrusive->new->dist_dir($path)->find_modules;

my $json = $coder->encode({%$deps});
print $json;

