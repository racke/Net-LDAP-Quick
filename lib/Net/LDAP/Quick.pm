package Net::LDAP::Quick;

use 5.006;
use strict;
use warnings;

=head1 NAME

Net::LDAP::Quick - Quick methods for LDAP

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

=cut

use Net::LDAP;
use Net::LDAP::Quick::Handle;
use YAML qw/LoadFile/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw/ldap/;

my $settings = undef;
my %handles;
my $def_handle = {};

sub ldap () {
    my $arg = shift;
    _load_ldap_settings() unless $settings;
    
    # The key to use to store this handle in %handles.  This will be either the
    # name supplied to database(), the hashref supplied to database() (thus, as
    # long as the same hashref of settings is passed, the same handle will be
    # reused) or $def_handle if database() is called without args:
    my $handle_key;
    my $conn_details;           # connection settings to use.
    my $handle;

    # Accept a hashref of settings to use, if desired.  If so, we use this
    # hashref to look for the handle, too, so as long as the same hashref is
    # passed to the database() keyword, we'll reuse the same handle:
    if (ref $arg eq 'HASH') {
        $handle_key = $arg;
        $conn_details = $arg;
    } else {
        $handle_key = defined $arg ? $arg : $def_handle;
        $conn_details = _get_settings($arg);
        if (!$conn_details) {
            die "No LDAP settings for " . ($arg || "default connection");
        }
    }

    #   Dancer::Logger::debug("Details: ", $conn_details);

    # To be fork safe and thread safe, use a combination of the PID and TID (if
    # running with use threads) to make sure no two processes/threads share
    # handles.  Implementation based on DBIx::Connector by David E. Wheeler.
    my $pid_tid = $$;
    $pid_tid .= '_' . threads->tid if $INC{'threads.pm'};

    # OK, see if we have a matching handle
    $handle = $handles{$pid_tid}{$handle_key} || {};

    if ($handle->{dbh}) {
        if ($conn_details->{connection_check_threshold} &&
            time - $handle->{last_connection_check}
            < $conn_details->{connection_check_threshold}) {
            return $handle->{dbh};
        } else {
            if (_check_connection($handle->{dbh})) {
                $handle->{last_connection_check} = time;
                return $handle->{dbh};
            } else {
                if ($handle->{dbh}) {
                    $handle->{dbh}->disconnect;
                }
                return $handle->{dbh}= _get_connection($conn_details);
            }
        }
    } else {
        # Get a new connection
        if ($handle->{dbh} = _get_connection($conn_details)) {
            $handle->{last_connection_check} = time;
            $handles{$pid_tid}{$handle_key} = $handle;
            return $handle->{dbh};
        } else {
            return;
        }
    }
}
;

# Try to establish a LDAP connection based on the given settings
sub _get_connection {
    my $settings = shift;
    my ($ldap, $ldret);

    unless ($ldap = Net::LDAP->new($settings->{uri})) {
        die "LDAP connection to $settings->{uri} failed: " . $@;
    }

    $ldret = $ldap->bind($settings->{bind},
                         password => $settings->{password});

    if ($ldret->code) {
        die 'LDAP bind failed (' . $ldret->code . '): ' . $ldret->error;
    }
    
    # pass reference to the settings
    $ldap->{_quick_settings} = $settings;
    return bless $ldap, 'Net::LDAP::Quick::Handle';
}

# Check whether the connection is alive
sub _check_connection {
    my $ldap = shift;
    return unless $ldap;
    return unless $ldap->socket;
    return 1;
}

sub _get_settings {
    my $name = shift;
    my $return_settings;

    # If no name given, just return the default settings
    if (!defined $name) {
        $return_settings = { %$settings };
    } else {
        # If there are no named connections in the config, bail now:
        return unless exists $settings->{connections};


        # OK, find a matching config for this name:
        if (my $settings = $settings->{connections}{$name}) {
            $return_settings = { %$settings };
        } else {
            die "Asked for a database handle named '$name' but no matching  "
              ."connection details found in config";
        }
    }

    # We should have soemthing to return now; make sure we have a
    # connection_check_threshold, then return what we found.  In previous
    # versions the documentation contained a typo mentioning
    # connectivity-check-threshold, so support that as an alias.
    if (exists $return_settings->{'connectivity-check-threshold'}
        && !exists $return_settings->{connection_check_threshold}) {
        $return_settings->{connection_check_threshold}
          = delete $return_settings->{'connectivity-check-threshold'};
    }

    $return_settings->{connection_check_threshold} ||= 30;
    return $return_settings;

}

sub _load_ldap_settings {
    foreach my $f (qw/ldap.yaml ldap.yml .ldap.yml .ldap.yaml/) {
        if (-f $f) {
            $settings = LoadFile($f);
            last;
        }
    }
    if ($settings) {
        return $settings;
    }
    else {
        die "No ldap.yaml found in current directory!";
    }
}

=head1 AUTHOR

Marco Pessotto, C<< <melmothx at gmail.com> >>

=head1 ACKNOWLEDGEMENTS

Code mostly stolen from Dancer::Plugin::LDAP by Stefan Hornburg (Racke)

=head1 LICENSE AND COPYRIGHT

This software is copyright (c) 2019 by Marco Pessotto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

1;                              # End of Net::LDAP::Quick
