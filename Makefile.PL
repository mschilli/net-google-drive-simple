######################################################################
# Makefile.PL for Net::Google::Drive::Simple
# 2012, Mike Schilli <cpan@perlmeister.com>
######################################################################
use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'         => 'Net::Google::Drive::Simple',
    'VERSION_FROM' => 'lib/Net/Google/Drive/Simple.pm', # finds $VERSION
    'PREREQ_PM'    => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/Net/Google/Drive/Simple.pm',
       AUTHOR     => 'Mike Schilli <cpan@perlmeister.com>') : ()),
);
