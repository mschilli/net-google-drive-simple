use strict;
use warnings;

on 'runtime' => sub {
    requires 'File::MMagic'         => '1.29';
    requires 'JSON'                 => '2.53';
    requires 'Log::Log4perl'        => '1';
    requires 'LWP::Protocol::https' => '6.04';
    requires 'LWP::UserAgent'       => '6.02';
    requires 'Mojolicious'          => '4.13';
    requires 'OAuth::Cmdline'       => '0.07';
    requires 'Pod::Usage'           => '1.36';
    requires 'Sysadm::Install'      => '0.43';
    requires 'YAML'                 => '0.71';
};

on 'configure' => sub {
    requires 'ExtUtils::MakeMaker';
};

on 'test' => sub {
    requires "Test2::V0"                 => "0";
    requires "Test2::Tools::Explain"     => "0";
    requires "Test2::Plugin::NoWarnings" => "0";
    requires "File::Temp"                => "0";
    requires "Test::MockModule"          => "0.171";
};

on 'develop' => sub {
    requires 'Pod::Coverage::TrustPod';
    requires 'Test::CheckManifest' => '1.29';
    requires 'Test::CPAN::Changes' => '0.4';
    requires 'Test::CPAN::Meta';
    requires 'Test::Kwalitee' => '1.22';
    requires 'Test::Pod::Coverage';
    requires 'Test::Pod::Spelling::CommonMistakes' => '1.000';
};
