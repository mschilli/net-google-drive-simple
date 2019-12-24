requires 'strict';

requires 'OAuth::Cmdline'  => '0.0';
requires 'File::MMagic'    => '>= 1.29';
requires 'JSON'            => '>= 2.53';
requires 'Log::Log4perl'   => '>= 1';
requires 'Mojolicious'     => '>= 4.13';
requires 'Pod::Usage'      => '>= 1.36';
requires 'Sysadm::Install' => '>= 0.43';
requires 'YAML'            => '>= 0.71';

on "test" => sub {
    requires "Test2::Bundle::Extended"   => "0";
    requires "Test2::Tools::Explain"     => "0";
    requires "Test2::Plugin::NoWarnings" => "0";
    requires "File::Temp"                => "0";
    requires "Test::MockModule"          => "v0.171.0";
};

# do not install them on GitHub action containers
on "recommends" => sub {
    requires 'Crypt::SSLeay'        => '>= 0.72';
    requires 'LWP::Protocol::https' => '>= 6.04';
    requires 'LWP::UserAgent'       => '>= 6.02';
};
