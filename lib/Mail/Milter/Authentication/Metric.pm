package Mail::Milter::Authentication::Metric;
use strict;
use warnings;
use version; our $VERSION = version->declare('v1.1.1');

use English qw{ -no_match_vars };

sub new {
    my ( $class ) = @_;
    my $self = {};
    $self->{'counter'} = {};
    $self->{'help'}    = {};
    bless $self, $class;
    return $self;
}

sub count {
    my ( $self, $id, $server ) = @_;
    my $psocket = $server->{'server'}->{'parent_sock'};
    print $psocket "METRIC.COUNT $id\n";
}

sub register {
    my ( $self, $id, $help, $server ) = @_;
    my $psocket = $server->{'server'}->{'parent_sock'};
    print $psocket "METRIC.REGISTER $id $help\n";
}

sub master_handler {
    my ( $self, $request, $socket, $server ) = @_;

    eval {
        local $SIG{'ALRM'} = sub{ die "Timeout\n" };
        alarm( 2 );

        my $ident = '{ident="' . lc ( $Mail::Milter::Authentication::Config::IDENT ) . '"}';

        my $guage_help = {
            'waiting'    => 'The number of authentication milter processes in a waiting state',
            'processing' => 'The number of authentication milter processes currently processing data',
        };

        if ( $request =~ /^METRIC.GET/ ) {
            foreach my $type ( qw { waiting processing } ) {
                print $socket '# TYPE authmilter_processes_' . $type . " gauge\n";
                print $socket '# HELP authmilter_processes_' . $type . ' ' . $guage_help->{ $type } . "\n";
                print $socket 'authmilter_' . $type . $ident . ' ' . $server->{'server'}->{'tally'}->{ $type } . "\n";
            }
            foreach my $key ( sort keys %{ $self->{'counter'} } ) {
                print $socket '# TYPE authmilter_' . $key . " counter\n";
                my $help = $self->{'help'}->{ $key };
                if ( $help ) {
                    print $socket '# HELP authmilter_' . $key . ' ' . $self->{'help'}->{ $key } . "\n";
                }
                print $socket 'authmilter_' . $key . $ident . ' ' . $self->{'counter'}->{ $key } . "\n";
            }
            print $socket "\0\n";
        }
        elsif ( $request =~ /^METRIC.REGISTER (.*)$/ ) {
            my $data = $1;
            my ( $count_id, $help ) = split ( ' ', $data, 2 );
            if ( ! exists( $self->{'counter'}->{ $count_id } ) ) {
                $self->{'counter'}->{ $count_id } = 0;
            }
            $self->{'help'}->{ $count_id } = $help;
        }
        elsif ( $request =~ /^METRIC.COUNT (.*)$/ ) {
            my $count_id = $1;
            if ( ! exists( $self->{'counter'}->{ $count_id } ) ) {
                $self->{'counter'}->{ $count_id } = 0;
            }
            $self->{'counter'}->{ $count_id }++;
        }

        alarm( 0 );
    };

    return;
}

sub child_handler {
    my ( $self, $server ) = @_;

    eval {
        local $SIG{'ALRM'} = sub{ die "Timeout\n" };
        alarm( 2 );

        my $socket = $server->{'server'}->{'client'};
        my $req;
    
        $PROGRAM_NAME = $Mail::Milter::Authentication::Config::IDENT . ':metrics';

        $req = <$socket>;
        $req =~ s/[\n\r]+$//;

        if (!defined($req) || $req !~ m{ ^\s*(GET|POST|PUT|DELETE|PUSH|HEAD|OPTIONS)\s+(.+)\s+(HTTP/1\.[01])\s*$ }ix) {
#            die "Invalid request\n";
            return;
        }

        my $request_method  = uc $1;
        my $request_uri     = $2;
        my $server_protocol = $3;
        if ( $request_method   ne 'GET' || $request_uri      ne '/metrics/' ) {
            print $socket "HTTP/1.0 500 Server Error\n";
            print $socket "\n";
            print $socket "Server Error\n";
            return;
        }

        # Ignore the rest of the HTTP request
        while ( $req = <$socket> ) {
            $req =~ s/[\n\r]+$//;
            last if $req eq q{};
        }

        my $psocket = $server->{'server'}->{'parent_sock'};
        print $psocket "METRIC.GET\n";

        print $socket "HTTP/1.0 200 OK\n";
        print $socket "Content-Type: text/plain\n";
        print $socket "\n";
        while ( my $value = <$psocket> ) {
            $value =~ s/[\n\r]+$//;
            last if $value eq "\0";
            print $socket "$value\n";
        }

        alarm( 0 );
    };

    return;
}

1;