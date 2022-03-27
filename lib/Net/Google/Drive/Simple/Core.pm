###########################################
package Net::Google::Drive::Simple::Core;
###########################################

use strict;
use warnings;

use LWP::UserAgent ();
use HTTP::Request  ();

use File::MMagic ();
use IO::File     ();

use OAuth::Cmdline::CustomFile  ();
use OAuth::Cmdline::GoogleDrive ();

use Net::Google::Drive::Simple::Item ();

use JSON qw( from_json to_json );
use Log::Log4perl qw(:easy);

our $VERSION = '0.22';

###########################################
sub new {
###########################################
    my ( $class, %options ) = @_;

    my $oauth;

    if ( exists $options{custom_file} ) {
        $oauth = OAuth::Cmdline::CustomFile->new( custom_file => $options{custom_file} );
    }
    else {
        $oauth = OAuth::Cmdline::GoogleDrive->new();
    }

    my $self = {
        init_done => undef,
        oauth     => $oauth,
        error     => undef,
        %options,
    };

    bless $self, $class;
}

###########################################
sub error {
###########################################
    my ( $self, $set ) = @_;

    if ( defined $set ) {
        $self->{error} = $set;
    }

    return $self->{error};
}

###########################################
sub init {
###########################################
    my ( $self, $path ) = @_;

    if ( $self->{init_done} ) {
        return 1;
    }

    DEBUG "Testing API";
    if ( !$self->api_test() ) {
        LOGDIE "api_test failed";
    }

    $self->{init_done} = 1;

    return 1;
}

###########################################
sub api_test {
###########################################
    my ($self) = @_;

    my $url = $self->file_url( { maxResults => 1 } );

    my $ua = LWP::UserAgent->new();

    my $req = HTTP::Request->new(
        GET => $url->as_string,
    );
    $req->header( $self->{oauth}->authorization_headers() );
    DEBUG "Fetching $url";

    my $resp = $ua->request($req);

    if ( $resp->is_success() ) {
        DEBUG "API tested OK";
        return 1;
    }

    $self->error( $resp->message() );

    ERROR "API error: ", $resp->message();
    return 0;
}

###########################################
sub data_factory {
###########################################
    my ( $self, $data ) = @_;

    return Net::Google::Drive::Simple::Item->new($data);
}

###########################################
sub http_loop {
###########################################
    my ( $self, $req, $noinit ) = @_;

    my $ua = LWP::UserAgent->new();
    my $resp;

    my $RETRIES        = 3;
    my $SLEEP_INTERVAL = 10;

    {
        # refresh token if necessary
        if ( !$noinit ) {
            $self->init();
        }

        DEBUG "Fetching ", $req->url->as_string();

        $resp = $ua->request($req);

        if ( !$resp->is_success() ) {
            $self->error( $resp->message() );
            warn "Failed with ", $resp->code(), ": ", $resp->message(), "\n";
            if ( --$RETRIES >= 0 ) {
                ERROR "Retrying in $SLEEP_INTERVAL seconds";
                sleep $SLEEP_INTERVAL;
                $self->{oauth}->token_expire();
                $req->header( $self->{oauth}->authorization_headers() );
                redo;
            }
            else {
                ERROR "Out of retries.";
                return $resp;
            }
        }

        DEBUG "Successfully fetched ", length( $resp->content() ), " bytes.";
    }

    return $resp;
}

###########################################
sub http_json {
###########################################
    my ( $self, $url, $post_data ) = @_;

    my @headers = ( $self->{'oauth'}->authorization_headers() );
    my $verb    = 'GET';
    my $content;
    if ($post_data) {
        if ( ref $post_data eq 'ARRAY' ) {
            ( $verb, $post_data ) = @{$post_data};
        } else {
            $verb = 'POST';
        }

        if ($post_data) {
            push @headers, "Content-Type", "application/json";
        }

        defined $post_data
            and $content = to_json($post_data);
    }

    my $req = HTTP::Request->new(
        $verb,
        $url->as_string(),
        \@headers,
        $content,
    );

    my $resp = $self->http_loop($req);

    if ( $resp->is_error() ) {
        $self->error( $resp->message() );
        return;
    }

    my $data = from_json( $resp->content() );

    return $data;
}

###########################################
sub file_mime_type {
###########################################
    my ( $self, $file ) = @_;

    # There don't seem to be great implementations of mimetype
    # detection on CPAN, so just use this one for now.

    if ( !$self->{magic} ) {
        $self->{magic} = File::MMagic->new();
    }

    return $self->{magic}->checktype_filename($file);
}

###########################################
sub item_iterator {
###########################################
    my ( $self, $data ) = @_;

    my $idx = 0;

    if ( !defined $data ) {
        die "no data in item_iterator";
    }

    return sub {
        {
            my $next_item = $data->{items}->[ $idx++ ];

            return if !defined $next_item;

            if ( $next_item->{labels}->{trashed} ) {
                DEBUG "Skipping $next_item->{ title } (trashed)";
                redo;
            }

            return $next_item;
        }
    };
}

###########################################
sub file_url {
###########################################
    my ( $self, $opts ) = @_;

    $opts = {} if !defined $opts;

    my $default_opts = {
        maxResults => 3000,
    };

    $opts = {
        %$default_opts,
        %$opts,
    };

    my $url = URI->new( $self->{api_file_url} );
    $url->query_form($opts);

    return $url;
}

###########################################
sub file_metadata {
###########################################
    my ( $self, $file_id ) = @_;

    LOGDIE 'Deletion requires file_id' if ( !defined $file_id );

    my $url = URI->new( $self->{api_file_url} . "/$file_id" );

    return $self->http_json($url);
}

###########################################
sub _content_sub {
###########################################
    my $self      = shift;
    my $filename  = shift;
    my @stat      = stat $filename;
    my $remaining = $stat[7];
    my $blksize   = $stat[11] || 4096;

    die "$filename not a readable file with fixed size"
      unless -r $filename
      and $remaining;

    my $fh = IO::File->new( $filename, 'r' )
      or die "Could not open $filename: $!";
    $fh->binmode;

    return sub {
        my $buffer;

        # upon retries the file is closed and we must reopen it
        unless ( $fh->opened ) {
            $fh = IO::File->new( $filename, 'r' )
              or die "Could not open $filename: $!";
            $fh->binmode;
            $remaining = $stat[7];
        }

        unless ( my $read = $fh->read( $buffer, $blksize ) ) {
            die "Error while reading upload content $filename ($remaining remaining) $!"
              if $! and $remaining;
            $fh->close    # otherwise, we found EOF
              or die "close of upload content $filename failed: $!";
            $buffer ||= '';    # LWP expects an empty string on finish, read returns 0
        }
        $remaining -= length($buffer);
        return $buffer;
    };
}

1;

__END__

=pod

=head1 DESCRIPTION

This is a baseclass that the V2 and V3 implementations of the module use.
You shouldn't use this class directly.

=head1 METHODS

These are methods that are shared among L<Net::Google::Drive::Simple::V2>
and L<Net::Google::Drive::Simple::V3>.

You wouldn't normally use these methods.

=head2 C<error>

Set and retrieve the current error.

=head2 C<init>

Internal initialization to setup the connection.

=head2 C<api_test>

Used at init time to check that the connection is correct.

=head2 C<data_factory>

Set up an object of L<Net::Google::Drive::Simple::Item>.

=head2 C<http_json>

Make an HTTP request with a body.

=head2 C<http_loop>

Perform a request.

=head2 C<file_metadata>

    my $metadata_hash_ref = $gd->file_metadata($fileId);

Return metadata about the file with the specified ID from Google Drive.

=head2 C<file_url>

Retrieve a file URL.

=head2 C<file_mime_type>

Retrieve the mime type of a file.

=head2 C<item_iterator>

Create an iterator over items.

=head2 C<path_resolve>

Resolve paths to the folder ID.
