######################################################################
# Test suite for Net::Google::Drive::Simple
# by Mike Schilli <cpan@perlmeister.com>
######################################################################
use warnings;
use strict;

use Test::More;

plan tests => 1;

use Net::Google::Drive::Simple;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

my $gd = Net::Google::Drive::Simple->new();

my $files = $gd->children( "/top/books-chunks", { maxResults => 3 } );

for my $file ( @$files ) {
    print "$file->{ title }\n";
}
