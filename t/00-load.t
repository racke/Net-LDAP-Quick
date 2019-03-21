#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Net::LDAP::Quick' ) || print "Bail out!\n";
}

diag( "Testing Net::LDAP::Quick $Net::LDAP::Quick::VERSION, Perl $], $^X" );
