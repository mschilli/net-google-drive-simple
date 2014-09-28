######################################################################
# Test suite for Net::Google::Drive::Simple
# by Mike Schilli <cpan@perlmeister.com>
######################################################################
use warnings;
use strict;

use FindBin qw( $Bin );
use Test::More;

my $nof_tests      = 8;
my $nof_live_tests = 7;
plan tests => $nof_tests;

use Net::Google::Drive::Simple;
use Log::Log4perl qw(:easy);

# Log::Log4perl->easy_init( { level => $DEBUG, layout => "%F{1}:%L> %m%n" } );

my $gd = Net::Google::Drive::Simple->new();

ok 1, "loaded ok";

SKIP: {
    if( !$ENV{ LIVE_TEST } ) {
        skip "LIVE_TEST not set, skipping live tests", $nof_live_tests;
    }

    my( $files, $parent ) = $gd->children( "/", 
        { maxResults => 3 }, { page => 0 },
    );

    # upload a test file
    my $testfile = "$Bin/data/testfile";
    my $file_id = $gd->file_upload( $testfile, $parent );
    ok defined $file_id, "upload ok";
    ok $gd->file_delete( $file_id ), "delete ok";

    is ref($files), "ARRAY", "children returned ok";

    $files = $gd->children( "/", 
        { maxResults => 3 }, { page => 0 },
    );

    is ref($files), "ARRAY", "scalar context children";

    $files = $gd->files( { maxResults => 3 }, { page => 0 } );
    is ref($files), "ARRAY", "files found";

    ( $files ) = $gd->files( { maxResults => 10 }, { page => 0 },
    );
    is ref($files), "ARRAY", "files found";
    ok length $files->[0]->originalFilename(), "org filename";
}
