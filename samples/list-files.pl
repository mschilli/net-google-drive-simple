#!perl

use strict;
use warnings;

use feature 'say';

use Net::Google::Drive::Simple;

my $gd = Net::Google::Drive::Simple->new();
my $children = $gd->children("/") or die "Google::Drive failure: $!";

foreach my $child (@$children) {
    if ( $child->is_folder ) {
        say "** ", $child->title, " is a folder";
    }
    else {
        say $child->title, " is a file ", $child->mimeType;
    }
}
