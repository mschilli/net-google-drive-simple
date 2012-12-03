######################################################################
# Test suite for Net::Google::Drive::Simple
# by Mike Schilli <cpan@perlmeister.com>
######################################################################
use warnings;
use strict;

use Test::More;

plan tests => 1;

use Net::Google::Drive::Simple;

my $gd = Net::Google::Drive::Simple->new();

my $files = $gd->files(
    { maxResults => 5,
    }
);

print "@$files\n";
