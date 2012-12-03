###########################################
package Net::Google::Drive::Simple;
###########################################
use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Headers;
use HTTP::Request::Common;
use File::Basename;
use YAML qw( LoadFile DumpFile );
use JSON qw( from_json );
use Log::Log4perl qw(:easy);
use Data::Dumper;

our $VERSION = "0.01";

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        config_file => undef,
        %options,
    };

    if( ! $self->{ config_file } ) {
        my( $home )  = glob "~";
        $self->{ config_file } = "$home/.google-drive.yml";
    }

    bless $self, $class;
}

###########################################
sub init {
###########################################
    my( $self, $path ) = @_;

    if( $self->{ init_done } and
        ! $self->token_expired() ) {
        return 1;
    }

    my $cfg = {};

    if( ! -f $self->{ config_file } ) {
        LOGDIE "$self->{ config_file } not found.";
    }

    $cfg = LoadFile $self->{ config_file };
    $self->{ cfg } = $cfg;

    $self->token_refresh( $cfg );
    DumpFile( $self->{ config_file }, $cfg );

    $self->{ cfg } = $cfg;

    $self->{ init_done } = 1;

    return 1;
}

###########################################
sub token_expired {
###########################################
    my( $self ) = @_;

    my $time_remaining = $self->{ cfg }->{ expires } - time();

    if( $time_remaining < 60 ) {

        if( $time_remaining < 0 ) {
            INFO "Token expired $time_remaining seconds ago";
        } else {
            INFO "Token will expire in $time_remaining seconds";
        }

        INFO "Token needs to be refreshed.";

        return 1;
    }

    return 0;
}

###########################################
sub files {
###########################################
    my( $self, $opts ) = @_;

    $self->init();

    if( !defined $opts ) {
        $opts = { 
            maxResults => 2,
        };
    }

    my $url = URI->new( "https://www.googleapis.com/drive/v2/files" );
    $url->query_form( $opts );

    my $data = $self->http_json( $url );
    
    my @docs = ();
    
    for my $item ( @{ $data->{ items } } ) {
    
        # ignore trash
      next if $item->{ labels }->{ trashed };
    
      if( $item->{ kind } eq "drive#file" ) {
        my $file = $item->{ originalFilename };
        next if !defined $file; 
    
          # ignore non-pdf
        next if $file !~ /\.pdf$/i;
    
        push @docs, $file;
      }
    }

    return \@docs;
}

###########################################
sub children_by_folder_id {
###########################################
    my( $self, $folder_id, $opts) = @_;

    $self->init();

    if( !defined $opts ) {
        $opts = { 
            maxResults => 100,
        };
    }

    my $url = URI->new( 
        "https://www.googleapis.com/drive/v2/files/$folder_id/children" );

    $url->query_form( $opts );

    my $data = $self->http_json( $url );

    my @children = ();

    for my $item ( @{ $data->{ items } } ) {
        my $uri = URI->new( $item->{ childLink } );
        my $data = $self->http_json( $uri );
        push @children, $data;
    }

    return \@children;
}

###########################################
sub children {
###########################################
    my( $self, $path, $opts ) = @_;

    if( !defined $path ) {
        LOGDIE "No $path given";
    }

    my @parts = split '/', $path;
    $parts[0] = "root";

    my $folder_id = shift @parts;
    my $self_link;

    PART: for my $part ( @parts ) {
        DEBUG "Looking up part $part (folder_id=$folder_id)";
        my $children = $self->children_by_folder_id( $folder_id );

        for my $child ( @$children ) {
            DEBUG "Found child $child->{ title }";
            if( $child->{ title } eq $part ) {
                $folder_id = $child->{ id };
                $self_link = $child->{ self_link };
                next PART;
            }
        }

        LOGDIE "Child $part not found";
    }

    INFO "Getting content of folder";

    my $children = $self->children_by_folder_id( $folder_id, $opts );

    return $children;
}

###########################################
sub json_factory {
###########################################
    my( $self, $class, $json ) = @_;

      # Transform JSON data into an object of the specified class, providing
      # accessors for all fields set
    my $json_data = from_json( $json );

    bless $json_data, $class;
}

###########################################
sub token_refresh {
###########################################
  my( $self, $cfg ) = @_;

  my $req = &HTTP::Request::Common::POST(
    'https://accounts.google.com/o' .
    '/oauth2/token',
    [
      refresh_token => 
        $cfg->{ refresh_token },
      client_id     => 
        $cfg->{ client_id },
      client_secret => 
        $cfg->{ client_secret },
      grant_type    => 'refresh_token',
    ]
  );

  my $ua = LWP::UserAgent->new();
  my $resp = $ua->request($req);

  if ( $resp->is_success() ) {
    my $data = from_json( $resp->content() );
    $cfg->{ access_token } = 
      $data->{ access_token };
    $cfg->{ expires } = 
      time() + $data->{ expires_in };
    return 1;
  }

  INFO $resp->status_line();
  return undef;
}

###########################################
sub http_json {
###########################################
    my( $self, $url ) = @_;

    my $req = HTTP::Request->new(
      GET => $url->as_string,
      HTTP::Headers->new( Authorization => 
          "Bearer " . $self->{ cfg }->{ access_token })
    );

    my $ua = LWP::UserAgent->new();
    my $resp = $ua->request( $req );

    if( ! $resp->is_success() ) {
        die $resp->message();
    }

    my $data = from_json( $resp->content() );

    return $data;
}
    
1;

__END__

=head1 NAME

Net::Google::Drive::Simple - Simple modification of Google Drive data

=head1 SYNOPSIS

    use Net::Google::Drive::Simple;

    my $gd = Net::Google::Drive::Simple->new();

    my $children = $gd->children( "/top/books" );

    for my $child ( @$children ) {

        next if $child->kind() ne 'drive#file';

        print $child->originalFilename(), 
              " can be downloaded at ",
              $child->downloadUrl(), 
              "\n";
    }

=head1 DESCRIPTION

Net::Google::Drive::Simple authenticates with a user's Google Drive and
offers several convenience methods to list, retrieve, and modify the data
stored in the cloud.

=head1 LEGALESE

Copyright 2012 by Mike Schilli, all rights reserved.
This program is free software, you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 AUTHOR

2012, Mike Schilli <cpan@perlmeister.com>
