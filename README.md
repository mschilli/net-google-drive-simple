# NAME

Net::Google::Drive::Simple - Simple modification of Google Drive data

# SYNOPSIS

```perl
use feature 'say';
use Net::Google::Drive::Simple;

# requires a ~/.google-drive.yml file with an access token,
# see description below.
my $gd = Net::Google::Drive::Simple->new();                 # old, v2 interface
my $gd = Net::Google::Drive::Simple->new( 'version' => 3 ); # new, v3 interface

my $children = $gd->children( "/" ); # or any other folder /path/location

foreach my $item ( @$children ) {

    # item is a Net::Google::Drive::Simple::Item object

    if ( $item->is_folder ) {
        say "** ", $item->title, " is a folder";
    } else {
        say $item->title, " is a file ", $item->mimeType;
        eval { # originalFilename not necessary available for all files
          say $item->originalFilename(), " can be downloaded at ", $item->downloadUrl();
        };
    }
}
```

# DESCRIPTION

Net::Google::Drive::Simple authenticates with a user's Google Drive and
offers several convenience methods to list, retrieve, and modify the data
stored in the 'cloud'. See `eg/google-drive-upsync` as an example on how
to keep a local directory in sync with a remote directory on Google Drive.

All methods are documented based on the version you use:

- V2 (default)

    ```perl
    # Create default V2 API:
    my $gd = Net::Google:Drive::Simple->new();

    # or:
    my $gd = Net::Google:Drive::Simple->new( 'version' => 2 );
    ```

    The methods available are documented in
    [Net::Google::Drive::Simple::V2](https://metacpan.org/pod/Net%3A%3AGoogle%3A%3ADrive%3A%3ASimple%3A%3AV2).

- V3 (new)

    ```perl
    # Create default V3 API:
    my $gd = Net::Google:Drive::Simple->new( 'version' => 3 );
    ```

    The methods available are documented in
    [Net::Google::Drive::Simple::V3](https://metacpan.org/pod/Net%3A%3AGoogle%3A%3ADrive%3A%3ASimple%3A%3AV3).

## GETTING STARTED

To get the access token required to access your Google Drive data via
this module, you need to run the script `eg/google-drive-init` in this
distribution.

Before you run it, you need to register your 'app' with Google Drive
and obtain a client\_id and a client\_secret from Google:

```
https://developers.google.com/drive/web/enable-sdk
```

Click on "Enable the Drive API and SDK", and find "Create an API project in
the Google APIs Console". On the API console, create a new project, click
"Services", and enable "Drive API" (leave "drive SDK" off). Then, under
"API Access" in the navigation bar, create a client ID, and make sure to
register a an "installed application" (not a "web application"). "Redirect
URIs" should contain "http://localhost". This will get you a "Client ID"
and a "Client Secret".

Then, replace the following lines in `eg/google-drive-init` with the
values received:

```perl
  # You need to obtain a client_id and a client_secret from
  # https://developers.google.com/drive to use this.
my $client_id     = "XXX";
my $client_secret = "YYY";
```

Then run the script. It'll start a web server on port 8082 on your local
machine.  When you point your browser at http://localhost:8082, you'll see a
link that will lead you to Google Drive's login page, where you authenticate
and then allow the app (specified by client\_id and client\_secret above) access
to your Google Drive data. The script will then receive an access token from
Google Drive and store it in ~/.google-drive.yml from where other scripts can
pick it up and work on the data stored on the user's Google Drive account. Make
sure to limit access to ~/.google-drive.yml, because it contains the access
token that allows everyone to manipulate your Google Drive data. It also
contains a refresh token that this library uses to get a new access token
transparently when the old one is about to expire.

# METHODS

- `new()`

    Constructor, creates a helper object to retrieve Google Drive data
    later.

    By default, this returns an object of
    [Net::Google::Drive::Simple::V2](https://metacpan.org/pod/Net%3A%3AGoogle%3A%3ADrive%3A%3ASimple%3A%3AV2) which implements version 2 of the
    Google Drive API.

    While that API version is still available, the new version is recommended
    and you create an object of it by passing the `version` parameter:

    ```perl
    my $gd = Net::Google::Drive::Simple->new( 'version' => 3 );
    ```

    This will return an object of [Net::Google::Drive::Simple::V3](https://metacpan.org/pod/Net%3A%3AGoogle%3A%3ADrive%3A%3ASimple%3A%3AV3).

    Read up on the methods in each class.

# Error handling

In case of an error while retrieving information from the Google Drive
API, the methods above will return `undef` and a more detailed error
message can be obtained by calling the `error()` method:

```
print "An error occurred: ", $gd->error();
```

# LOGGING/DEBUGGING

Net::Google::Drive::Simple is Log4perl-enabled.
To find out what's going on under the hood, turn on Log4perl:

```perl
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
```

# LEGALESE

Copyright 2012-2019 by Mike Schilli, all rights reserved.
This program is free software, you can redistribute it and/or
modify it under the same terms as Perl itself.

# AUTHOR

2019, Nicolas R. <cpan@atoomic.org>
2012-2019, Mike Schilli <cpan@perlmeister.com>
