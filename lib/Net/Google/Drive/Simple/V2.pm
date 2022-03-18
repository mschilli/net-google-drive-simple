###########################################
package Net::Google::Drive::Simple::V2;
###########################################

use strict;
use warnings;

use parent qw< Net::Google::Drive::Simple::Core >;
use LWP::UserAgent ();
use HTTP::Request  ();

use File::Basename qw( basename );

use JSON qw( from_json to_json );
use Log::Log4perl qw(:easy);

our $VERSION = '0.22';

###########################################
sub new {
###########################################
    my ( $class, %options ) = @_;
    return $class->SUPER::new(
        %options,
        api_file_url   => 'https://www.googleapis.com/drive/v2/files',
        api_upload_url => 'https://www.googleapis.com/upload/drive/v2/files',
    );
}

###########################################
sub files {
###########################################
    my ( $self, $opts, $search_opts ) = @_;

    if ( !defined $search_opts ) {
        $search_opts = {};
    }
    $search_opts = {
        page => 1,
        %$search_opts,
    };

    if ( !defined $opts ) {
        $opts = {};
    }

    $self->init();

    if ( my $title = $search_opts->{title} ) {
        $title =~ s|\'|\\\'|g;
        if ( defined $opts->{q} && length $opts->{q} ) {
            $opts->{q} .= ' AND ';
        }

        $opts->{q} .= "title = '$title'";
    }

    my @docs = ();

    while (1) {
        my $url  = $self->file_url($opts);
        my $data = $self->http_json($url);
        return unless defined $data;
        my $next_item = $self->item_iterator($data);

        while ( my $item = $next_item->() ) {
            if ( $item->{kind} eq "drive#file" ) {
                my $file = $item->{originalFilename};
                if ( !defined $file ) {
                    DEBUG "Skipping $item->{ title } (no originalFilename)";
                    next;
                }

                push @docs, $self->data_factory($item);
            }
            else {
                DEBUG "Skipping $item->{ title } ($item->{ kind })";
            }
        }

        if ( $search_opts->{page} and $data->{nextPageToken} ) {
            $opts->{pageToken} = $data->{nextPageToken};
        }
        else {
            last;
        }
    }

    return \@docs;
}

###########################################
sub folder_create {
###########################################
    my ( $self, $title, $parent ) = @_;

    return $self->file_create( $title, "application/vnd.google-apps.folder", $parent );
}

###########################################
sub file_create {
###########################################
    my ( $self, $title, $mime_type, $parent ) = @_;

    my $url = URI->new( $self->{api_file_url} );

    my $data = $self->http_json(
        $url,
        {
            title    => $title,
            parents  => [ { id => $parent } ],
            mimeType => $mime_type,
        }
    );

    return unless defined $data;

    return $data->{id};
}

###########################################
sub file_upload {
###########################################
    my ( $self, $file, $parent_id, $file_id, $opts ) = @_;

    $opts = {} if !defined $opts;

    # Since a file upload can take a long time, refresh the token
    # just in case.
    $self->{oauth}->token_expire();

    my $title = basename $file;

    # First, insert the file placeholder, according to
    # http://stackoverflow.com/questions/10317638
    my $mime_type = $self->file_mime_type($file);

    my $url;

    if ( !defined $file_id ) {
        $url = URI->new( $self->{api_file_url} );

        my $data = $self->http_json(
            $url,
            {
                mimeType    => $mime_type,
                parents     => [ { id => $parent_id } ],
                title       => $opts->{title} ? $opts->{title} : $title,
                description => $opts->{description},
            }
        );

        return unless defined $data;

        $file_id = $data->{id};
    }

    $url = URI->new( $self->{api_upload_url} . "/$file_id" );
    $url->query_form( uploadType => "media" );

    my $file_length = -s $file;
    my $file_data   = $self->_content_sub($file);

    if (
        $self->http_put(
            $url,
            {
                'Content-Type'   => $mime_type,
                'Content'        => $file_data,
                'Content-Length' => $file_length
            }
        )
    ) {
        return $file_id;
    }
}

###########################################
sub rename {
###########################################
    my ( $self, $file_id, $new_name ) = @_;

    my $url = URI->new( $self->{api_file_url} . "/$file_id" );

    if (
        $self->http_put(
            $url,
            {
                "Accept"       => "application/json",
                "Content-Type" => "application/json",
                Content        => to_json( { title => $new_name } ),
            }
        )
    ) {
        return 1;
    }
    return;

}

###########################################
sub http_put {
###########################################
    my ( $self, $url, $params ) = @_;

    my $content = delete $params->{Content};
    my $req     = HTTP::Request->new(
        'PUT',
        $url->as_string,
        [ $self->{oauth}->authorization_headers(), %$params ],
    );

    # $content can be a string or a CODE ref. For example rename() calls us with a string, but
    #  file_upload() calls us with a CODE ref. The HTTP::Request::new() only accepts a string,
    #  so we set the content of the request after calling the constructor.
    $req->content($content);
    my $resp = $self->http_loop($req);

    if ( $resp->is_error ) {
        $self->error( $resp->message() );
        return;
    }
    DEBUG $resp->as_string;
    return $resp;
}

###########################################
sub file_mvdir {
###########################################
    my ( $self, $path, $target_folder ) = @_;

    my $url;

    if ( !defined $path or !defined $target_folder ) {
        LOGDIE "Missing parameter";
    }

    # Determine the file's parent in the path
    my ( $file_id, $folder_id ) = $self->path_resolve($path);

    if ( !defined $file_id ) {
        LOGDIE "Cannot find source file: $path";
    }

    my ($target_folder_id) = $self->path_resolve($target_folder);

    if ( !defined $target_folder_id ) {
        LOGDIE "Cannot find destination path: $target_folder";
    }

    print "file_id=$file_id\n";
    print "folder_id=$folder_id\n";
    print "target_folder_id=$target_folder_id\n";

    # Delete it from the current parent
    $url = URI->new( $self->{api_file_url} . "/$folder_id/children/$file_id" );
    if ( !$self->http_delete($url) ) {
        LOGDIE "Failed to remove $path from parent folder.";
    }

    # Add a new parent
    $url = URI->new( $self->{api_file_url} . "/$target_folder_id/children" );
    if ( !$self->http_json( $url, { id => $file_id } ) ) {
        LOGDIE "Failed to insert $path into $target_folder.";
    }

    return 1;
}

###########################################
sub path_resolve {
###########################################
    my ( $self, $path, $search_opts ) = @_;

    $search_opts = {} if !defined $search_opts;

    my @parts = grep { $_ ne '' } split '/', $path;

    my @ids       = qw(root);
    my $folder_id = my $parent = "root";
    DEBUG "Parent: $parent";

  PART: for my $part (@parts) {

        DEBUG "Looking up part $part (folder_id=$folder_id)";

        my $children = $self->children_by_folder_id(
            $folder_id,
            {
                maxResults => 100,    # path resolution maxResults is different
            },
            { %$search_opts, title => $part },
        );

        return unless defined $children;

        for my $child (@$children) {
            DEBUG "Found child ", $child->title();
            if ( $child->title() eq $part ) {
                $folder_id = $child->id();
                unshift @ids, $folder_id;
                $parent = $folder_id;
                DEBUG "Parent: $parent";
                next PART;
            }
        }

        my $msg = "Child $part not found";
        $self->error($msg);
        ERROR $msg;
        return;
    }

    if ( @ids == 1 ) {

        # parent of root is root
        return ( @ids, @ids );
    }

    return (@ids);
}

###########################################
sub file_delete {
###########################################
    my ( $self, $file_id ) = @_;

    my $url;

    LOGDIE 'Deletion requires file_id' if ( !defined $file_id );

    $url = URI->new( $self->{api_file_url} . "/$file_id" );

    if ( $self->http_delete($url) ) {
        return $file_id;
    }

    return;
}

###########################################
sub http_delete {
###########################################
    my ( $self, $url ) = @_;

    my $req = HTTP::Request->new(
        'DELETE',
        $url,
        [ $self->{oauth}->authorization_headers() ],
    );

    my $resp = $self->http_loop($req);

    DEBUG $resp->as_string;

    if ( $resp->is_error ) {
        $self->error( $resp->message() );
        return;
    }

    return 1;
}

###########################################
sub children_by_folder_id {
###########################################
    my ( $self, $folder_id, $opts, $search_opts ) = @_;

    $self->init();

    $search_opts         = {} unless defined $search_opts;
    $search_opts->{page} = 1  unless exists $search_opts->{page};

    if ( !defined $opts ) {
        $opts = {
            maxResults => 100,
        };
    }

    my $url = URI->new( $self->{api_file_url} );
    $opts->{'q'} = "'$folder_id' in parents";

    if ( my $title = $search_opts->{title} ) {
        $title =~ s|\'|\\\'|g;
        $opts->{q} .= " AND title = '$title'";
    }

    my @children = ();

    while (1) {
        $url->query_form($opts);

        my $data = $self->http_json($url);
        return unless defined $data;

        my $next_item = $self->item_iterator($data);

        while ( my $item = $next_item->() ) {
            push @children, $self->data_factory($item);
        }

        if ( $search_opts->{page} and $data->{nextPageToken} ) {
            $opts->{pageToken} = $data->{nextPageToken};
        }
        else {
            last;
        }
    }

    return \@children;
}

###########################################
sub children {
###########################################
    my ( $self, $path, $opts, $search_opts ) = @_;

    DEBUG "Determine children of $path";
    LOGDIE "No $path given" unless defined $path;

    $search_opts = {} unless defined $search_opts;

    my ( $folder_id, $parent ) = $self->path_resolve( $path, $search_opts );

    return unless defined $folder_id;

    DEBUG "Getting content of folder $folder_id";
    my $children = $self->children_by_folder_id(
        $folder_id, $opts,
        $search_opts
    );

    return unless defined $children;

    return wantarray ? ( $children, $folder_id ) : $children;
}

###########################################
sub search {
###########################################
    my ( $self, $opts, $search_opts, $query ) = @_;
    $search_opts ||= { page => 1 };

    $self->init();

    if ( !defined $opts ) {
        $opts = {
            maxResults => 100,
        };
    }

    my $url = URI->new( $self->{api_file_url} );

    $opts->{'q'} = $query;

    my @children = ();

    while (1) {
        $url->query_form($opts);

        my $data = $self->http_json($url);
        return unless defined $data;

        my $next_item = $self->item_iterator($data);

        while ( my $item = $next_item->() ) {
            push @children, $self->data_factory($item);
        }

        if ( $search_opts->{page} and $data->{nextPageToken} ) {
            $opts->{pageToken} = $data->{nextPageToken};
        }
        else {
            last;
        }
    }

    return \@children;
}

###########################################
sub download {
###########################################
    my ( $self, $url, $local_file ) = @_;

    $self->init();

    if ( ref $url ) {
        $url = $url->downloadUrl();
    }

    my $req = HTTP::Request->new(
        GET => $url,
    );
    $req->header( $self->{oauth}->authorization_headers() );

    my $ua   = LWP::UserAgent->new();
    my $resp = $ua->request( $req, $local_file );

    if ( $resp->is_error() ) {
        my $msg = "Can't download $url (" . $resp->message() . ")";
        ERROR $msg;
        $self->error($msg);
        return;
    }

    if ($local_file) {
        return 1;
    }

    return $resp->content();
}

1;
