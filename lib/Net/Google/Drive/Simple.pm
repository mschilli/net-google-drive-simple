###########################################
package Net::Google::Drive::Simple;
###########################################
use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Headers;
use HTTP::Request::Common;
use Sysadm::Install qw( :all );
use File::Basename;
use YAML qw( LoadFile DumpFile );
use JSON qw( from_json to_json );
use Test::MockObject;
use Log::Log4perl qw(:easy);
use Data::Dumper;

our $VERSION = "0.01";

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        config_file => undef,
        api_file_url    => "https://www.googleapis.com/drive/v2/files",
        api_upload_url  => "https://www.googleapis.com/upload/drive/v2/files",
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

    if( $time_remaining < 300 ) {

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
            maxResults => 3000,
        };
    }

    my @docs = ();
        
    while( 1 ) {
        my $url = URI->new( $self->{ api_file_url } );
        $url->query_form( $opts );

        my $data = $self->http_json( $url );
    
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

        if( $data->{ nextPageToken } ) {
            $opts->{ pageToken } = $data->{ nextPageToken };
        } else {
            last;
        }
    }

    return \@docs;
}

###########################################
sub folder_create {
###########################################
    my( $self, $title, $parent ) = @_;

    my $url = URI->new( $self->{ api_file_url } );

    my $data = $self->http_json( $url, {
        title    => $title,
        parents  => [ { id => $parent } ],
        mimeType => "application/vnd.google-apps.folder",
    } );

    return $data->{ id };
}

###########################################
sub file_upload {
###########################################
    my( $self, $file, $parent_id, $file_id ) = @_;

    my $title = basename $file;

      # First, insert the file placeholder, according to
      # http://stackoverflow.com/questions/10317638
    my $pdf_data = slurp $file;

    my $url;

    if( ! defined $file_id ) {
        $url = URI->new( $self->{ api_file_url } );

        my $data = $self->http_json( $url, 
            { mimeType => "application/pdf",
              parents  => [ { id => $parent_id } ],
              title    => $title,
            }
        );

        $file_id = $data->{ id };
    }

    $url = URI->new( $self->{ api_upload_url } . "/$file_id" );
    $url->query_form( uploadType => "media" );

    my $req = &HTTP::Request::Common::PUT(
        $url->as_string,
        Authorization  => "Bearer " . $self->{ cfg }->{ access_token },
        "Content-Type" => "application/pdf",
        Content        => $pdf_data,
    );

    my $resp = $self->http_loop( $req );

    DEBUG $resp->as_string;

    return $file_id;
}

###########################################
sub children_by_folder_id {
###########################################
    my( $self, $folder_id, $opts, $search_opts ) = @_;

    $self->init();

    if( !defined $search_opts ) {
        $search_opts = {};
    }

    $search_opts = {
        page => 1,
        %$search_opts,
    };

    if( !defined $opts ) {
        $opts = { 
            maxResults => 100,
        };
    }

    my $url = URI->new( $self->{ api_file_url } );
    $opts->{ q } = "'$folder_id' in parents";

    if( $search_opts->{ title } ) {
        $opts->{ q } .= " AND title = '$search_opts->{ title }'";
    }

    my @children = ();
    
    while( 1 ) {
        $url->query_form( $opts );

        my $data = $self->http_json( $url );

        for my $item ( @{ $data->{ items } } ) {
            push @children, $self->data_factory( $item );
        }

        if( $search_opts->{ page } and $data->{ nextPageToken } ) {
            $opts->{ pageToken } = $data->{ nextPageToken };
        } else {
            last;
        }
    }
    
    return \@children;
}

###########################################
sub children {
###########################################
    my( $self, $path, $opts, $search_opts ) = @_;

    if( !defined $path ) {
        LOGDIE "No $path given";
    }

    if( !defined $search_opts ) {
        $search_opts = {};
    }

    my @parts = split '/', $path;
    my $parent = $parts[0] = "root";
    DEBUG "Parent: $parent";

    my $folder_id = shift @parts;

    PART: for my $part ( @parts ) {

        DEBUG "Looking up part $part (folder_id=$folder_id)";

        my $children = $self->children_by_folder_id( $folder_id, 
          { maxResults    => 100, # path resolution maxResults is different
          },
          { %$search_opts, title => $part },
        );

        for my $child ( @$children ) {
            DEBUG "Found child ", $child->title();
            if( $child->title() eq $part ) {
                $folder_id = $child->id();
                $parent = $folder_id;
                DEBUG "Parent: $parent";
                next PART;
            }
        }

        LOGDIE "Child $part not found";
    }

    DEBUG "Getting content of folder";

    my $children = $self->children_by_folder_id( $folder_id, $opts, 
        $search_opts );

    return( $children, $parent );
}

###########################################
sub data_factory {
###########################################
    my( $self, $data ) = @_;

    my $mock = Test::MockObject->new();

    for my $key ( keys %$data ) {
        # DEBUG "Adding method $key";
        $mock->mock( $key , sub { $data->{ $key } } );
    }

    return $mock;
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

  my $resp = $self->http_loop( $req, 1 );

  if ( $resp->is_success() ) {
    my $data = from_json( $resp->content() );
    $cfg->{ access_token } = 
      $data->{ access_token };
    $cfg->{ expires } = 
      time() + $data->{ expires_in };
    return 1;
  }

  DEBUG $resp->status_line();
  return undef;
}

###########################################
sub http_loop {
###########################################
    my( $self, $req, $noinit ) = @_;

    my $ua = LWP::UserAgent->new();
    my $resp;

    my $RETRIES        = 3;
    my $SLEEP_INTERVAL = 10;

    {
        DEBUG "Fetching ", $req->url->as_string;

          # refresh token if necessary
        if( ! $noinit ) {
            $self->init();
        }

        $resp = $ua->request( $req );

        if( ! $resp->is_success() ) {
            warn "Failed with ", $resp->code(), ": ", $resp->message();
            if( --$RETRIES >= 0 ) {
                ERROR "Retrying in $SLEEP_INTERVAL seconds";
                sleep $SLEEP_INTERVAL;
                redo;
            } else {
                die "Out of retries.";
            }
        }

        DEBUG "Successfully fetched ", length( $resp->content() ), " bytes.";
    }

    return $resp;
}

###########################################
sub http_json {
###########################################
    my( $self, $url, $post_data ) = @_;

    my $req;

    if( $post_data ) {
        $req = &HTTP::Request::Common::POST(
            $url->as_string,
            Authorization => "Bearer " . $self->{ cfg }->{ access_token },
            "Content-Type"=> "application/json",
            Content       => to_json( $post_data ),
        );
    } else {
      $req = HTTP::Request->new(
        GET => $url->as_string,
        HTTP::Headers->new( Authorization => 
            "Bearer " . $self->{ cfg }->{ access_token })
      );
    }

    DEBUG "Fetching ", $req->as_string();

    my $resp = $self->http_loop( $req );

    my $data = from_json( $resp->content() );

    return $data;
}
    
1;

__END__

=head1 NAME

Net::Google::Drive::Simple - Simple modification of Google Drive data

=head1 SYNOPSIS

    use Net::Google::Drive::Simple;

      # requires a ~/.google-drive.yml file with an access token, 
      # see description below.
    my $gd = Net::Google::Drive::Simple->new();

    my $children = $gd->children( "/folder/path" );

    for my $child ( @$children ) {

        next if $child->kind() ne 'drive#file';

        next if !$child->can( "downloadUrl" );

        print $child->originalFilename(), 
              " can be downloaded at ",
              $child->downloadUrl(), 
              "\n";
    }

=head1 DESCRIPTION

Net::Google::Drive::Simple authenticates with a user's Google Drive and
offers several convenience methods to list, retrieve, and modify the data
stored in the 'cloud'. See C<eg/google-drive-upsync> as an example on how
to keep a local directory in sync with a remote directory on Google Drive.

=head2 GETTING STARTED

To get the access token required to access your Google Drive data via 
this module, you need to run the script C<eg/google-drive-init> in this
distribution.

Before you run it, you need to register your 'app' with Google Drive
and obtain a client_id and a client_secret from

    https://developers.google.com/drive

Then, replace the following lines in C<eg/google-drive-init> with the
values received:

      # You need to obtain a client_id and a client_secret from
      # https://developers.google.com/drive to use this.
    my $client_id     = "XXX";
    my $client_secret = "YYY";

Then run the script. It'll start a web server on port 8082 on your local
machine.  When you point your browser at http://localhost:8082, you'll see a
link that will lead you to Google Drive's login page, where you authenticate
and then allow the app (specified by client_id and client_secret above) access
to your Google Drive data. The script will then receive an access token from
Google Drive and store it in ~/.google-drive.yml from where other scripts can
pick it up and work on the data stored on the user's Google Drive account. Make
sure to limit access to ~/.google-drive.yml, because it contains the access
token that allows everyone to manipulate your Google Drive data. It also
contains a refresh token that this library uses to get a new access token
transparently when the old one is about to expire.

=head1 METHODS

=over 4

=item C<new()>

Constructor, creates a helper object to retrieve Google Drive data
later. Takes an optional name of the C<.google-drive.yml> file

    my $gd = Net::Google::Drive::Simple->new(
        config_file => "gd.yml",
    );

or uses C<~/.google-drive.yml> in the user's home directory as default.

=item C<my $children = $gd-E<gt>children( "/path/to" )>

Return the entries under a given path on the Google Drive as a reference
to an array. Each entry 
is an object composed of the JSON data returned by the Google Drive API.
Each object offers methods named like the fields in the JSON data, e.g.
C<originalFilename()>, C<downloadUrl>, etc.

Will return all entries found unless C<maxResults> is set:

    my $children = $gd->children( "/path/to", { maxResults => 3 } )

Due to the somewhat capricious ways Google Drive handles its directory
structures, the method needs to traverse the path component by component
and determine the ID of each directory to get to the next level. To speed
up subsequent lookups, it also returns the ID of the last component to the
caller:

    my( $children, $parent ) = $gd->children( "/path/to" );

If the caller now wants to e.g. insert a file into the directory, its 
ID is available in $parent.

Each child comes back as a files#resource type and gets mapped into
an object that offers access to the various fields via methods:

    for my $child ( @$children ) {
        print $child->kind(), " ", $child->title(), "\n";
    }

Please refer to 

    https://developers.google.com/drive/v2/reference/files#resource

for details on which fields are available.

=item C<my $files = $gd-E<gt>files( )>

Return all files on the drive as a reference to an array.
Will return all entries found unless C<maxResults> is set:

    my $files = $gd->files( "/path/to", { maxResults => 3 } )

Note that Google limits the number of entries returned by default to
100, and seems to restrict the maximum number of files returned
by a single query to 3,500, even if you specify higher values for
C<maxResults>.

Each file comes back as an object that offers access to the Google
Drive item's fields, according to the API (see C<children()>).

=item C<my $id = $gd-E<gt>folder_create( "folder-name", $parent_id )>

Create a new folder as a child of the folder with the id C<$parent_id>.
Returns the ID of the new folder or undef in case of an error.

=item C<$gd-E<gt>file_upload( $file, $dir_id )>

Uploads the content of the file C<$file> into the directory with the ID
$dir_id on Google Drive. Uses C<$file> as the file name. 

To overwrite an existing file on Google Drive, specify the file's ID as
an optional parameter:

    $gd->file_upload( $file, $dir_id, $file_id );

=back

=head1 LOGGING/DEBUGGING

Net::Google::Drive::Simple is Log4perl-enabled.
To find out what's going on under the hood, turn on Log4perl:

    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($DEBUG);

=head1 LEGALESE

Copyright 2012 by Mike Schilli, all rights reserved.
This program is free software, you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 AUTHOR

2012, Mike Schilli <cpan@perlmeister.com>
