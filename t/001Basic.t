######################################################################
# Test suite for Net::Google::Drive::Simple
# by Mike Schilli <cpan@perlmeister.com>
######################################################################
use warnings;
use strict;

use Test::More;

plan tests => 4;

use Net::Google::Drive::Simple;
use Log::Log4perl qw(:easy);

# Log::Log4perl->easy_init( { level => $DEBUG, layout => "%F{1}:%L> %m%n" } );

my $gd = Net::Google::Drive::Simple->new();

ok 1, "loaded ok";

SKIP: {
    if( !$ENV{ LIVE_TEST } ) {
        skip "LIVE_TEST not set, skipping live tests", 3;
    }

    my( $files, $parent ) = $gd->children( "/", 
        { maxResults => 3 }, { page => 0 },
    );

    is ref($files), "ARRAY", "children returned ok";

    $files = $gd->children( "/", 
        { maxResults => 3 }, { page => 0 },
    );

    is ref($files), "ARRAY", "scalar context children";

    $files = $gd->files( { maxResults => 3 }, { page => 0 } );
    is ref($files), "ARRAY", "files found";
}
