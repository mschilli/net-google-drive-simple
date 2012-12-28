######################################################################
# Test suite for Net::Google::Drive::Simple
# by Mike Schilli <cpan@perlmeister.com>
######################################################################
use warnings;
use strict;

use Test::More;

plan tests => 2;

use Net::Google::Drive::Simple;
use Log::Log4perl qw(:easy);

# Log::Log4perl->easy_init($DEBUG);

my $gd = Net::Google::Drive::Simple->new();

ok 1, "loaded ok";

SKIP: {
    if( !$ENV{ LIVE_TEST } ) {
        skip "LIVE_TEST not set, skipping live tests", 1;
    }

    my( $files, $parent ) = $gd->children( "/", 
        { maxResults => 3 }, { page => 0 },
    );

    ok $files, "children returned ok";
}
