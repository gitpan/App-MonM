package App::MonM; # $Id: MonM.pm 42 2014-12-17 12:33:09Z abalama $
use strict;

=head1 NAME

App::MonM - Simple Monitoring Tools

=head1 VERSION

Version 1.03

=head1 SYNOPSIS

    use App::MonM;
    use CTK;
    use CTKx;
    CTKx->instance( c => new CTK );
    
    my $monm = new App::MonM;

=head1 ABSTRACT

App::MonM - Simple Monitoring Tools

=head1 DESCRIPTION

Simple Monitoring Tools

=head1 METHODS

=over 8

=item B<new>

    my $monm = new App::MonM( %OPTIONS );

Returns object. The %OPTIONS contains options of command line. See L<Getopt::Long> for details

=item B<opt>

    $monm->opt( 'verbose' );

Returns value of option-key

=item B<status>

    $monm->status( 1 );
    print $monm->status ? 'OK' : 'ERROR';

Set/Get status. Method returns current status

=item B<message>

    $monm->message( "message" );
    print $monm->message;

Set/Get message. Method returns informational message

=item B<error>

    $monm->error( "error1", "error2", ... );
    print $monm->error;

Set/Get error message. Method returns all current error messages separated by newline-chars

=item B<lasterror>

    $monm->error( "error1", "error2" );
    $monm->error( "error3" );
    print $monm->lasterror; # returns: error3

Method returns only last-added error messages separated by newline-chars

=item B<void>

    my $status = $monm->void;
    print $monm->message if $status;

The method returns status of "void" request. See L<monm> and README for details

=item B<test>

    my $status = $monm->test;
    print $monm->message if $status;

The method returns status of "test" request. See L<monm> and README for details

=item B<dbi>

    my $status = $monm->dbi( 'name' );
    print $monm->message if $status;

The method returns status of "dbi" request. See L<monm> and README for details

=item B<http>

    my $status = $monm->http( 'name' );
    print $monm->message if $status;

The method returns status of "http" request. See L<monm> and README for details

=item B<checkit>

    my $status = $monm->checkit( 'count' );
    print $monm->message if $status;

The method returns status of "checkit" request. See L<monm> and README for details

=item B<alertgrid_init, alertgrid_clear, alertgrid_config, alertgrid_server, alertgrid_client, alertgrid_snapshot, alertgrid_export>

    my $status = $monm->alertgrid_server( '' );
or
    my $status = $monm->alertgrid_client( 'name' );

The group of methods, each of which returns status of "alertgrid" request. 
See L<monm> and README for details

=item B<rrdtool_create, rrdtool_update, rrdtool_graph, rrdtool_index>

    my $status = $monm->rrdtool_init;

The group of methods, each of which returns status of "rrdtool" request. 
See L<monm> and README for details

=back

=head1 HISTORY

See C<CHANGES> file

=head1 DEPENDENCIES

L<CTK>

=head1 TO DO

See C<TODO> file

=head1 BUGS

* none noted

=head1 SEE ALSO

C<perl>, L<CTK>

=head1 AUTHOR

Serz Minus (Lepenkov Sergey) L<http://www.serzik.com> E<lt>minus@mail333.comE<gt>

=head1 COPYRIGHT

Copyright (C) 1998-2014 D&D Corporation. All Rights Reserved

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

See C<LICENSE> file

=cut

use vars qw/ $VERSION /;
$VERSION = '1.03';

use CTKx;
use CTK::Util;
use CTK::ConfGenUtil;
use CTK::TFVals qw/ :ALL /;
use CTK::DBI;

use Encode; # Encode::_utf8_on();
use Text::Unidecode;

use JSON;
use Text::SimpleTable;
use YAML::Tiny qw/Dump/;
use XML::Simple;
use Data::Dumper; $Data::Dumper::Deparse = 1;

use Try::Tiny;

#use File::Path; # mkpath / rmtree
use File::Spec;

# libwww
use URI;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Cookies;
use TemplateM;

use App::MonM::Util;
use App::MonM::Checkit;
use App::MonM::AlertGrid;
use App::MonM::RRDtool;

use constant {
    SCREENSTEP  => 9, # indent
    SCREENWIDTH => 80 - 9, # = <width> - <indent on test-status >
    FORMATS     => [qw/ yaml yml xml json text txt dump dmp none /],
    XMLDECL     => '<?xml version="1.0" encoding="utf-8"?>',
    AG_TIMEOUT  => 180,
    
    # Test-Statuses
    TRUE        => 1,
    FALSE       => 0,
    VOID        => '',
    OK          => "OK",        # for SMALL operations
    DONE        => "DONE",      # for LONG operations
    ERROR       => "ERROR",     # for operations
    SKIPPED     => "SKIPPED",   # for tests
    PASSED      => "PASSED",    # for tests
    FAILED      => "FAILED",    # for tests
};

our $SCREEN_INI;
our $SCREEN_W;
BEGIN {
    sub _screen_ini {
        unless (-t) {
            $SCREEN_W = SCREENWIDTH;
            return 1;
        }
        try {
            if (CTKx->instance->c->debugmode) {
                require Term::ReadKey;
                $SCREEN_W = (Term::ReadKey::GetTerminalSize())[0] - SCREENSTEP; 
                $SCREEN_W = SCREENWIDTH if $SCREEN_W < SCREENSTEP;
            } else {
                $SCREEN_W = SCREENWIDTH;
            }
        } catch {
            $SCREEN_W = SCREENWIDTH;
        };
        return 1;
    }
    sub debug { 
        local $| = 1; 
        print @_ ? (@_,"\n") : '' if CTKx->instance->c->debugmode;
    }
    sub start {
        my $s = uv2null(shift);
        my $l = length $s;
        if (CTKx->instance->c->debugmode) {
            $SCREEN_INI = _screen_ini unless $SCREEN_INI;
            printf("%s%s ", $s, ($l<$SCREEN_W?('.'x($SCREEN_W-$l)):''));
        }
    }
    sub finish { 
        local $| = 1;
        print((@_?@_:''), "\n") if CTKx->instance->c->debugmode;
    }
}

sub new {
    my $class = shift;
    my $ctkx = CTKx->instance;
    my $c = $ctkx->c;
    croak("The class is loaded without the required CTK object. CTK Object mismatch") unless $c && ref($c) =~ /CTK/;
    
    my $self = bless { 
            ctkx    => $ctkx,
            opts    => {@_}, # Command options ($::OPT)
            status  => TRUE,
            message => OK,
            error   => [],
            lasterror => VOID,
        }, $class;
    
    # ���������� �������
    unless (-t) {
        if ($self->opt("utf8")) {
            binmode STDIN,  ":raw:utf8";
            binmode STDOUT, ":raw:utf8";
            binmode STDERR, ":raw:utf8";
        } else {
            binmode STDIN;
            binmode STDOUT;
            binmode STDERR;
        }
    }
    
    return $self;
}
sub ctkx { return shift->{ctkx} }
sub opt {return uv2null(value(shift->{opts}, shift || 'qwertyuiop'))}
sub status { 
    my $self = shift;
    my $s = shift;
    $self->{status} = $s if defined $s;
    return $self->{status};
}
sub message { 
    my $self = shift;
    my $s = shift;
    $self->{message} = $s if defined $s;
    return $self->{message};
}
sub error { 
    my $self = shift;
    my $aerr = $self->{error};
    if (@_) {
        push @$aerr, @_;
        $self->{lasterror} = join("\n",@_);
    }
    return join("\n",@$aerr);
}
sub lasterror {
    my $self = shift;
    return $self->{lasterror};
}
sub void {
    my $self = shift;
    debug "VOID CONTEXT";

    # �����
    my $rslt = $self->foutput("void");

    # �������
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    
    $self->status;;
}
sub test {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    
    start "Testing";
    my @rslth = qw/foo bar baz/;
    my @rsltd = (
            [qw/qwe rty uiop/],
            [qw/asd fgh jkl/],
            [qw/zxc vbn m/],
        );

    my $cgsf = [];
    if (value($config,'loadstatus')) {
        $cgsf = array($config, 'configfiles') || [];
    }
    my $env = Dumper(\%ENV);
    my $inc = Dumper(\@INC);
    my $cfg = Dumper($config);
    finish DONE;
    if ($self->opt('verbose')) {
        debug "Directories:";
        debug "    DATADIR  : ",uv2null($c->datadir);
        debug "    LOGDIR   : ",uv2null($c->logdir);
        debug "    LOGFILE  : ",uv2null($c->logfile);
        debug "    CONFDIR  : ",uv2null($c->confdir);
        debug "    CONFFILE : ",uv2null($c->cfgfile);
        debug "Loaded configuration files:";
        debug("    ",($_ || '')) for (@$cgsf);
        debug "-----BEGIN ENV DUMP-----";
        debug $env;
        debug "-----END ENV DUMP-----";
        debug "-----BEGIN INC DUMP-----";
        debug $inc;
        debug "-----END INC DUMP-----";
        debug "-----BEGIN CFG DUMP-----";
        debug $cfg;
        debug "-----END CFG DUMP-----";
    }

    # �����
    my $rslt = $self->foutput("test", {
            logdir      => uv2null($c->logdir),
            logfile     => uv2null($c->logfile),
            confdir     => uv2null($c->confdir),
            conffile    => uv2null($c->cfgfile),
            datadir     => uv2null($c->datadir),
            voidfile    => uv2null($c->voidfile),
        }, \@rsltd, \@rslth);

    # �������
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    
    #::debug(Dumper($self));
    #::debug(Dumper(\%data));
    
    $self->status;
}
sub dbi {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;

    # ����������� ����������
    my $dbi_data = {};
    my $dbi_attr = {};
    
    # ��������� ����� ������ & ������ ���������� ������
    my $name = $data{args} && $data{args}[0] ? $data{args}[0] : '';
    if ($name) {
        # ��������� ������ ����� ���� ��� ������
        start "Loading DBI configuration data for $name";
        $dbi_data = hash($config, 'dbi', $name);
        if (keys %$dbi_data) {
            #foreach (keys %{(_get_attr($dbi_data))}) { print ">>> $_\n" };
            $dbi_attr = _get_attr($dbi_data);
            finish DONE;
            debug Dumper($dbi_data) if $self->opt('verbose');
        } else {
            finish ERROR;
            $self->error(sprintf("Incorrect configuration section <DBI %s>", $name));
            debug sprintf("Incorrect configuration section <DBI %s>", $name);
        }
    }
    my $attr = hash($data{attr});
    foreach my $ak (keys %$attr) {
        $dbi_attr->{$ak} = $attr->{$ak} unless exists($dbi_attr->{$ak});
    }
    debug sprintf("ATTR: %s", Dumper($dbi_attr)) if $self->opt('verbose');
    
    # SID && DSN
    my $dsn = "";
    my $sid = $self->opt("sid") || value($dbi_data, "sid");
    if ($sid) { # SID � ��������� �� ����� ��� � �������
        $dsn = sprintf("DBI:Oracle:%s", $sid);
    } else {
        $dsn = $self->opt("dsn") || value($dbi_data, "dsn") || '';
    }
    debug sprintf("DSN: %s", $dsn) if $self->opt('verbose');
    
    # SQL from STDIN, FILE, OPTION or CONFIG. Default from arguments
    my $sql = "";
    if ($self->opt("stdin")) {
        $sql = _read_stdin();
        #debug sprintf("Readed SQL from STDIN: %s", $sql);
    } elsif ($self->opt("input")) {
        my $fin = $self->opt("input");
        $sql = bload( $fin, $self->opt("utf8") ? 1 : 0 ) if -e $fin;
    }
    $sql ||= $self->opt("sql") || value($dbi_data, "sql") || $data{sql};
    Encode::_utf8_on($sql) if $self->opt("utf8");
    
    if ($self->opt('verbose')) {
        debug "-----BEGIN SQL-----";
        if ($self->opt("utf8")) {
            debug sprintf(to_utf8("SQL: %s"), $sql);
        } else {
            debug sprintf("SQL: %s", $sql);
        }
        debug "-----END SQL-----";
    }
    
    # DBI connect
    start "Connecting";
    my $connect_status  = FALSE;
    my $connect_message = VOID;
    my $dbi = new CTK::DBI(
            -dsn        => $dsn,
            -user       => $self->opt("user") || uv2null(value($dbi_data, "user")),
            -pass       => $self->opt("password") || uv2null(value($dbi_data, "password")),
            -connect_to => $self->opt("timeout") || value($dbi_data, "connect_to") || $data{timeout},
            -request_to => $self->opt("timeout") || value($dbi_data, "request_to") || $data{timeout},
            -attr       => $dbi_attr,
        );
    if ($dbi && $dbi->{dbh}) {
        $connect_status     = TRUE;
        $connect_message    = OK;
        finish OK;
    } else {
        $connect_status     = FALSE;
        $connect_message    = ERROR;
        finish ERROR;
        $self->error($DBI::errstr);
        debug $DBI::errstr;
    }
    
    # DBI Execute SQL
    start "SQL preparing and executing";
    my $execute_status  = FALSE;
    my $execute_message = VOID;
    my $sth;
    if ($connect_status) {
        $sth = $dbi->execute($sql);
        if ($sth) {
            $execute_status     = TRUE;
            $execute_message    = OK;
            finish OK;
        } else {
            $execute_message    = ERROR;
            finish ERROR;
            $self->error($DBI::errstr);
            debug $DBI::errstr;
        }
    } else {
        $execute_message    = SKIPPED;
        finish SKIPPED;
    }

    # Result fetching
    start "Result fetching";
    my $fetch_status    = FALSE;
    my $fetch_message   = VOID;
    my $rslt            = '';
    my $rsltc           = 0;
    my (@rslth, @rsltd);
    if ($execute_status) {
        @rsltd = @{$sth->fetchall_arrayref};
        $rsltc = $sth->rows || 0;
        @rslth = $sth->{NAME} ? @{$sth->{NAME}} : ();
        if ($rsltc && ! @rslth) {
            my $cfrow = scalar(@{$rsltd[0]}) || 0;
            @rslth = map {$_ = '#'.$_} (1..$cfrow);
        }
        $sth->finish;
        if ($rsltc && @rsltd) {
            $fetch_status       = TRUE;
            $fetch_message      = OK;
            finish OK;
        } else {
            $fetch_message      = ERROR;
            finish ERROR;
            debug "NO DATA";
        }
    } else {
        $fetch_message  = SKIPPED;
        finish SKIPPED;
    }
    
    # Disconnecting
    start "Disconnecting";
    my $disconnect_status   = FALSE;
    my $disconnect_message  = VOID;
    my $rc;
    if ($connect_status) {
        $rc = $dbi->{dbh}->disconnect();
        $dbi->{dbh} = undef;
        $disconnect_status   = TRUE;
        $disconnect_message  = OK;
        finish OK;
    } else {
        $disconnect_message  = SKIPPED;
        finish SKIPPED;
    }

    # ��������� ���� ��������
    unless ($connect_status && $execute_status && $fetch_status) {
        $self->status(FALSE);
        $self->message(ERROR);
    }
    
    # �����
    $rslt = $self->foutput("dbi", {
            connect     => $connect_message,
            execute     => $execute_message,
            fetch       => $fetch_message,
            disconnect  => $disconnect_message,
        }, \@rsltd, \@rslth);
    
    # �������
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    
    $self->status;
}
sub http {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;

    # ����������� ����������
    my $file = $self->opt("file"); # ���� ��� ��������� ���������
    my $http_data = {};
    my $http_attr = {};
    
    # ��������� ����� ������ & ������ ���������� ������
    my $name = $data{args} && $data{args}[0] ? $data{args}[0] : '';
    if ($name) {
        # ��������� ������ ����� ���� ��� ������
        start "Loading HTTP configuration data for $name";
        $http_data = hash($config, 'http', $name);
        if (keys %$http_data) {
            $http_attr = _get_attr($http_data);
            finish DONE;
            #debug Dumper($http_data) if $self->opt('verbose');
        } else {
            finish ERROR;
            $self->error(sprintf("Incorrect configuration section <HTTP %s>", $name));
            debug sprintf("Incorrect configuration section <HTTP %s>", $name);
        }
    }
    my $attr = hash($data{attr});
    foreach my $ak (keys %$attr) {
        $http_attr->{$ak} = $attr->{$ak} unless exists($http_attr->{$ak});
    }
    #debug sprintf("ATTR: %s", Dumper($http_attr)) if $self->opt('verbose');
    
    # ������������� utf8 ��������
    unless ($self->opt("utf8")) {
        if (value($http_data, 'utf8')) {
            $self->{opts}{utf8} = 1;
        }
    }

    # DATA from STDIN, FILE, OPTION or CONFIG. Default from CONFIG
    my $req_content = "";
    if ($self->opt("stdin")) {
        $req_content = _read_stdin();
    } elsif ($self->opt("input")) {
        my $fin = $self->opt("input");
        $req_content = bload( $fin, $self->opt("utf8") ? 1 : 0 ) if -e $fin;
    }
    $req_content ||= $self->opt("request") || uv2null(value($http_data, "data"));
    Encode::_utf8_on($req_content) if $self->opt("utf8");
    if ($self->opt('verbose') && (!$self->opt("stdin")) && (!$self->opt("input"))) {
        debug "-----BEGIN REQUEST CONTENT-----";
        debug $self->opt("utf8") ? unidecode($req_content) : $req_content;
        debug "-----END REQUEST CONTENT-----";
    }

    # ������ ����
    start "Setting Cookie";
    my $cookie_jar = undef;
    if (value($http_data, 'cookieenable')) {
        my %cookie;
        my $hhc = hash($http_data, 'cookie');
        $cookie{file} = catfile($c->datadir, sprintf("%s.cj", $c->prefix));
        $cookie{$_}   = value($hhc, $_) for (keys %$hhc);
        $cookie_jar = new HTTP::Cookies(%cookie);
        finish DONE;
        debug sprintf(to_utf8("COOKIE: %s"), Dumper($cookie_jar)) if $self->opt('verbose');
    } else {
        finish SKIPPED;
    }

    # �������������� ������ ������
    start "Preparing data";
    my %uaopt;
    my $hhua = hash($http_data, 'ua');
    $uaopt{agent} = __PACKAGE__."/".$VERSION;
    $uaopt{timeout} = $self->opt("timeout") || value($hhua, "timeout") || $data{timeout};
    $uaopt{cookie_jar} = $cookie_jar if $cookie_jar;
    for (keys %$hhua) {
        my $uas = node($hhua, $_);
        $uaopt{$_} = array($uas) if is_array($uas);
        $uaopt{$_} = value($uas) if is_value($uas);
        $uaopt{$_} = hash($uas) if is_hash($uas) && $_ ne 'header';
    }
    my $ua = new LWP::UserAgent(%uaopt); 
    
    # ������� ������ ��� ������
    my $hhh = hash($hhua, 'header');
    $ua->default_header($_, value($hhh, $_)) for (keys %$hhh);
    
    # �������������� �������
    my $httpct = {};
    $httpct->{'utf8'} = $self->opt("utf8") || value($http_data, 'utf8') || 0;
    my $method = uc($self->opt("method") || value($http_data, 'method') || "GET");
    $httpct->{method} = $method;
    my $url = $self->opt("url") || value($http_data, 'url') || '';
    $httpct->{url} = $url;
    my $login = $self->opt("user") || value($http_data, 'user') || value($http_data, 'login') || '';
    $httpct->{login} = $login if $login;
    my $passwd = $self->opt("password") || value($http_data, 'password') || '';
    $httpct->{password} = $passwd if $login && $passwd;
    
    # �������������� ������ ��� ������
    my $uri = new URI($url);
    $ua->add_handler( request_prepare => sub { 
            my($req, $ua, $h) = @_;
            $req->authorization_basic( $login, $passwd );
            return $req;
        } ) if $login;
    my $req = new HTTP::Request(uc($method), $uri);
    $req->header('Content-Type', ($method eq "POST") ? "application/x-www-form-urlencoded" : "text/plain") unless $req->header('Content-Type');
    my $req_content_length = length $req_content;
    $req->header('Content-Length', $req_content_length) unless $req->header('Content-Length'); # Not really needed
    $req->content($req_content) if defined($req_content) && $req_content ne "";
    finish DONE;
    #if ($self->opt('verbose')) { debug sprintf(to_utf8("UA: %s"), Dumper($ua)); debug sprintf(to_utf8("REQ: %s"), Dumper($req));}
    
    # ��������� ������
    start "Sending request";
    my $start_t = time; # Start time of download
    my $res = $ua->request($req, $file || undef);
    my $finish_t = time; # Finish time of download
    finish DONE;
    if ($self->opt('verbose')) {
        #debug sprintf(to_utf8("RES: %s"), Dumper($res));
        for my $r ($res->redirects) {
            _show_http_report($r, $method);
        }
        _show_http_report($res, $method);
    }
    
    
    start "Getting response";
    # ��������� ������. ������� ����������
    my %ret; # �������������� ��� ��� ������ ��������� ��������
    my $res_content = VOID;
    $ret{request_content_file}      = uv2null($self->opt("input"));
    $ret{request_method}            = $method;
    $ret{request_uri}               = $req->uri->as_string;
    $ret{request_headers}           = $res->request->headers_as_string;
    $ret{request_content_length}    = $req_content_length;
    
    $ret{response_content_file}     = uv2null($file);
    $ret{response_code}             = $res->code;
    $ret{response_message}          = $res->message;
    $ret{response_status_line}      = $res->status_line;
    $ret{response_headers}          = $res->headers_as_string;
    $ret{response_content_length}   = $res->content_length || 0;
    $ret{transaction_statistic}     = "";
    
    # �������� ������
    if ($res->is_success && !$res->header("X-Died")) {
        $ret{status} = TRUE;
        $self->status(TRUE);
        $self->message(OK);
        finish OK;
        
        my $length = $res->content_length;
        my $size = 0;
        if ($file) {
            debug sprintf("File has been saved in file: %s", $file);
            $size = -s $file;
        } else {
            if ($self->opt("utf8")) {
                $res_content = $res->content; # $res->decoded_content;
                $res_content = VOID unless defined $res_content;
                Encode::_utf8_on($res_content);
                {
                    use bytes;
                    $size = length($res_content);
                    no bytes;
                }
            } else {
                $res_content = $res->content;
                $res_content = VOID unless defined $res_content;
                $size = length($res_content);
            }
            
            if ($self->opt('verbose')) {
                debug "-----BEGIN RESPONSE CONTENT-----";
                debug $self->opt("utf8") ? unidecode($res_content) : $res_content;
                debug "-----END RESPONSE CONTENT-----";
            }
        }
        my $result_stat = "";
        if (defined($length) && $length != $size) {
            $result_stat = sprintf("%s (%d bytes) of %s (%d bytes) received", _fbytes($size), $size, _fbytes($length), $length);
        } else {
            $result_stat = sprintf("%s (%d bytes) received", _fbytes($size), $size);
        }
        my $dur = $finish_t - $start_t;
        $result_stat = sprintf("%s in %s (%s/sec)", $result_stat, _fduration($dur), _fbytes($size/$dur)) if $dur;
        $ret{transaction_statistic} = $result_stat;
        
    } else {
        $ret{status} = FALSE;
        $self->status(FALSE);
        $self->message(ERROR);
        finish ERROR;
        
        if (my $died = $res->header("X-Died")) {
            debug "$died";
            $self->error(sprintf("Error fetching data from %s: %s", $url, $died));
        } else {
            $self->error(sprintf("Error fetching data from %s: %s", $url, $res->status_line));
        }
        if ($file) {
            my $length = $res->content_length;
            my $size = -s $file;
            if (-t) {
                debug "Transfer aborted";
                $self->error("Transfer aborted");
                if ($length > $size) {
                    my $errmsg = sprintf("Truncated file kept: %s missing", _fbytes($length - $size));
                    debug $errmsg;
                    $self->error($errmsg);
                } else {
                    debug "File kept.";
                    $self->error("File kept.");
                }
            } else {
                debug "Transfer aborted, $file kept";
                $self->error("Transfer aborted, $file kept");
            }
        }
    }

    # �����
    my $rslt = $self->foutput("http", \%ret);

    # �������
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    
    $self->status;
}
sub checkit {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    my $name = $data{args} && $data{args}[0] ? $data{args}[0] : ''; # ��� ��������
    my $ymlfile = catfile($c->datadir,sprintf($data{ymlfile}, "")); # �������� �� ���������
    my $chreq   = 0;    # ���� ���� ��� ���-�� ����������!
    my @actions;        # �������������� ������� ��� ��������
    my @tabled;         # �������� ������� (������)
    my @trigd;          # �������� ������� ���������� ��������� (������)
    my %ret; # �������������� ���
   
    # ��������� ���������
    start "Loading configuration data";
    my $counts_node = node($config => 'checkit');
    my @clist = ();
    if ($counts_node && ref($counts_node) eq 'HASH') {
        if ($name) {
            @clist = grep {($_ eq lc($name)) && is_hash($counts_node, $_)} keys(%$counts_node);
            $ymlfile = catfile($c->datadir,sprintf($data{ymlfile}, lc($name))) if @clist;
        } else {
            @clist = grep {is_hash($counts_node, $_)} keys(%$counts_node);
        }
    }
    if (@clist) {
        finish DONE;
    } else {
        finish ERROR;
        $self->error("No counts found! Will be used all found counts");
        debug $self->lasterror;
        $c->log_info($self->lasterror);
    }
    #$c->log_debug(Dumper($ymlfile));
    
    # �������� ���� YAML
    start "Loading statistical data from file $ymlfile";
    my $yaml_in = {error => ''}; try { $yaml_in = YAML::Tiny::LoadFile($ymlfile) if -e $ymlfile } catch {$yaml_in->{error} = $_} ;
    my $yaml_out = {};
    finish $yaml_in->{error} ? ERROR : DONE;
    if ($yaml_in->{error}) {
        $self->error($yaml_in->{error});
        debug $self->lasterror;
        $c->log_error($self->lasterror);
    }
    #debug "Input YAML:\n",Dumper($yaml_in);
    
    # ��������������� �������� ��� ����������
    $c->log_debug("Start processing counts");
    my $pfx = " " x 3;
    foreach my $nc (sort {$a cmp $b} @clist) {
        start "Checking \"$nc\"";
        my $message = '';
        my $count = hash($counts_node,$nc);
        my $ydata = ($yaml_in->{$nc} && ref($yaml_in->{$nc}) eq 'ARRAY') ? $yaml_in->{$nc} : []; # �������� ���������� �� ����� YAML
        my ($status, $error) = readcount($count); # ���������� � ��������� ������� ���������� ��������

        # ������������ ������� ������
        my @newydata = @$ydata;
        my $corr = defined($newydata[0]) ? $newydata[0] : 0;
        $newydata[0] = defined($newydata[1]) ? $newydata[1] : 0;
        $newydata[1] = defined($newydata[2]) ? $newydata[2] : 0;
        $newydata[2] = ($status && $status eq 'OK') ? 1 : 0;
        
        # ������ ����������? �������� ����!
        $chreq = 1 if (join("",@$ydata) ne join("",@newydata));

        # ������� ������������ ��� ���������� ������
        $yaml_out->{$nc} = [@newydata];
        
        # ��������� ������ ������ � �������� ��������� ������ ��� ��������
        if (checkcount($corr,@newydata)) { # ������ ��������� �������!!
            $message = sprintf("%s: Available %s [%s]", ($status eq 'OK' ? 'OK' : 'PROBLEM'), $nc, join("-",$corr,@newydata));
            # ��������� ������ � ������� ��� ��������
            push @actions, {
                count       => $nc,
                countdata   => $count,
                message     => $message,
            };
        }

        # ��������� ��������
        finish $status;
        $c->log_debug($pfx, sprintf("%-5s %s",$status, $nc));
        if ($error) {
            debug $error;
            $c->log_warning($pfx x 2, $error);
        }
        if ($message) {
            debug $message;
            $c->log_debug($pfx x 2, $message);
        }
        
        #debug "New Array:\n",Dumper(\@newydata);
        #debug Dumper($cdata);
        #debug Dumper($ydata);
        push @tabled, [$nc,$status,$error];
    }
    $c->log_debug("Finish processing counts");
    
    # ���������� ���� ���� ������ ���-�� �� ����������
    if ($chreq) {
        try { YAML::Tiny::DumpFile($ymlfile, $yaml_out) } catch {
            $self->error("YAML::Tiny write error: $_");
            debug $self->lasterror;
            $c->log_error($self->lasterror);
        };
        CTK::carp("YAML::Tiny write error. Please check permissions for \"$ymlfile\"") unless -e $ymlfile;
    }

    # ��������� ������� �������� � ����������� ����������
    my $trigres = trigger($config, @actions);
    @trigd = @$trigres if $trigres && ref($trigres) eq 'ARRAY';

    # ��������������� ������
    #my $trig = result($OPT{output},\@trigh,\@trigd);
    #Encode::_utf8_on($trig) if $OPT{'utf8'} && !$OPT{charset};
    

    if ($self->opt('verbose') && @trigd) {
        my $trg_tbl = Text::SimpleTable->new(
                [40 => 'COUNT'],
                [8  => 'TYPE'],
                [26 => 'TO'],
                [64 => 'MESSAGE'],
                [8  => 'STATUS'],
            );
        $trg_tbl->row(@$_) for @trigd;
        my $trg = unidecode($trg_tbl->draw);
        debug "TRIGGERS:";
        debug $trg;
    }
    $ret{triggers} = Dumper(\@trigd);
    
    # ����� & �������
    my $rslt = $self->foutput("checkit", \%ret, \@tabled, [qw(COUNT STATUS MESSAGE)]);
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    
    $self->status;
}
sub alertgrid_init {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    
    my $dbfile = value($config, 'alertgrid/server/dbfile') || catfile($c->datadir,$data{dbfile});
    debug "DBFile: ", $dbfile;
    
    start "AlertGrid initialization";
    my $stt = ag_init($dbfile);
    my $msg = "";
    if ($stt) {
        finish DONE;
    } else {
        $self->status(FALSE);
        $self->message(SKIPPED);
        $self->error(sprintf "File %s already exists", $dbfile);
        finish SKIPPED;
    }
    
    # ����� / �������
    my $rslt = $self->foutput("alertgrid", {
            dbfile  => $dbfile,
        });
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    $self->status;
}
sub alertgrid_clear {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    
    my $dbfile = value($config, 'alertgrid/server/dbfile') || catfile($c->datadir,$data{dbfile});
    debug "DBFile: ", $dbfile;
    
    start "AlertGrid clearing";
    my $stt = ag_clear($dbfile);
    my $msg = "";
    if ($stt) {
        finish DONE;
    } else {
        $self->status(FALSE);
        $self->message(ERROR);
        $self->error(sprintf "File %s not exists", $dbfile);
        finish ERROR;
    }
    
    # ����� / �������
    my $rslt = $self->foutput("alertgrid", {
            dbfile  => $dbfile,
        });
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    $self->status;
}
sub alertgrid_config {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    
    # ����� / �������
    my $rslt = $self->foutput("alertgrid", {
            dbfile  => value($config, 'alertgrid/server/dbfile') || catfile($c->datadir,$data{dbfile}),
            name    => value($config, 'alertgrid/alertgridname'),
            ip      => value($config, 'alertgrid/agent/ip') || App::MonM::AlertGrid::LOCALHOSTIP(),
        });
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    $self->status;
}
sub alertgrid_snapshot {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    my $dbfile = value($config, 'alertgrid/server/dbfile') || catfile($c->datadir,$data{dbfile});
    my $snapshot;
    
    my $transfertype = value($config, "alertgrid/agent/transfertype") || 'http';
    if ($transfertype =~ /local/i) {
        debug "DBFile: ", $dbfile;
        $snapshot = ag_snapshot($dbfile);
    } else {
        my $doc = $self->_ag_remote_request(
                action  => "export",
                dbfile  => $dbfile,
            );
        if ($self->status) {
            if ($doc =~ s/^OK\r?\n\-\-\-\r?\n//i) {
                $snapshot = YAML::Tiny::Load($doc);
            } else {
                $snapshot = [];
            }
        }
    }
    
    my $th = [
            'id',
            'ip',
            'alertgrid',
            'count',
            'typ',
            'value',
            'pubdate',
            'expires',
            'err',
            'errmsg',
            'status',
        ];
    my $td = [];
    foreach my $row (@$snapshot) {
        push @$td, [
                $row->{id},
                $row->{ip},
                $row->{alertgrid_name},
                $row->{count_name},
                $row->{type},
                $row->{value},
                localtime2date_time($row->{pubdate}),
                localtime2date_time($row->{expires}),
                $row->{errcode},
                $row->{errmsg},
                $row->{status},
            ];
    }

    # ����� / �������
    my $rslt = $self->foutput("alertgrid", {
            dbfile  => $dbfile,
        }, $td, $th);
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    $self->status;
}
sub alertgrid_export {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    #my $mode = $data{args}; $mode = pop @$mode;
    my $dbfile = value($config, 'alertgrid/server/dbfile') || catfile($c->datadir,$data{dbfile});
    my $snapshot;
    
    my $transfertype = value($config, "alertgrid/agent/transfertype") || 'http';
    if ($transfertype =~ /local/i) {
        debug "DBFile: ", $dbfile;
        $snapshot = ag_snapshot($dbfile);
    } else {
        my $doc = $self->_ag_remote_request(
                action  => "export",
                dbfile  => $dbfile,
            );
        if ($self->status) {
            if ($doc =~ s/^OK\r?\n\-\-\-\r?\n//i) {
                $snapshot = YAML::Tiny::Load($doc);
            } else {
                $snapshot = [];
            }
        }
    }

    # ����� / �������
    my $rslt = $self->foutput("alertgrid", {
            dbfile  => $dbfile,
            counts  => {count => $snapshot},
        });
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    $self->status;
}
sub alertgrid_server {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;

    my $dbfile = value($config, 'alertgrid/server/dbfile') || catfile($c->datadir,$data{dbfile});
    debug "DBFile: ", $dbfile;
    
    # DATA from STDIN or FILE
    my $indata = "";
    if ($self->opt("stdin")) {
        $indata = _read_stdin();
    } elsif ($self->opt("input")) {
        my $fin = $self->opt("input");
        $indata = bload( $fin, $self->opt("utf8") ? 1 : 0 ) if -e $fin;
        debug "Data is unreadable" if $indata eq "";
    }
    #debug ">>>\n",$indata,"\n<<<";

    start "AlertGrid server starting";
    
    my ($stt, $err) = (0, ""); # Status, Error
    ($stt, $err) = ag_server({
                dbfile  => $dbfile,
                agentip => value($config, 'alertgrid/agent/ip'),
            }, 
            $indata
        );
    
    if ($stt) {
        finish DONE;
    } else {
        $self->status(FALSE);
        $self->message(ERROR);
        $self->error($err);
        finish ERROR;
    }
    
    # �����
    my $rslt = $self->foutput("alertgrid", {
            dbfile  => $dbfile,
        });

    # �������
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    
    $self->status;
}
sub alertgrid_client {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    my ($stt, $err) = (0, ""); # Status, Error

    my $dbfile = value($config, 'alertgrid/server/dbfile') || catfile($c->datadir,$data{dbfile});
    my $name = $data{args} && $data{args}[1] ? $data{args}[1] : ''; # ��� ��������
    debug "DBFile: ", $dbfile;

    # ��������� ������ ��������� ��� ���������
    if ($name) {
        start "Loading configuration data for count \"$name\"";
    } else {
        start "Loading configuration data";
    }
    my $counts_node = node($config => "alertgrid/count");
    my @clist = ();
    if ($counts_node && ref($counts_node) eq 'HASH') {
        if ($name) {
            @clist = grep {($_ eq lc($name)) && is_hash($counts_node, $_)} keys(%$counts_node);
        } else {
            @clist = grep {is_hash($counts_node, $_)} keys(%$counts_node);
        }
    }
    if (@clist) {
        finish DONE;
    } else {
        $self->error("No counts found!");
        $self->message(ERROR);
        $self->status(FALSE);
        finish ERROR;
    }

    # ��������������� �������� ��� ����������
    my @tableh = ('COUNT','VALUE','STATUS','MESSAGE'); # �������� ������� (���������)
    my @tabled; # �������� ������� (������)

    foreach my $count (@clist) {
        start "Getting data from \"$count\" count...";
        my $cdata = hash($counts_node, $count); # ��������� ���� ������ ��� ��������
        if (value($cdata, 'enable')) {
            my ($status, $result, $error) = ag_client({
                    type    => value($cdata, 'type'),
                    command => value($cdata, 'command'),
                });

            # ���������� ������� �������
            push @tabled, [$count,$result,$status,$error];
            finish $status ? OK : ERROR; 
            debug sprintf "Error: %s", $error if $error;
        } else {
            finish SKIPPED;
        }
    }
    #::debug Dumper(\@tabled);

    # ������ �� ������ �������������� ��������, � ������������ ������� ���������, ������� � �����������
    # ���������� �� HTTP ��������� �� ������. ������ ����������� ������� �� ������������
    my @summary;
    my $pubdate = time();
    foreach my $rec (@tabled) {
        my $base_count_name     = uv2void($rec->[0]) || 'noname';
        my $base_count_result   = hash($rec->[1]);
        my $base_count_status   = uv2void($rec->[2]);
        my $base_count_message  = uv2void($rec->[3]);
        next unless $base_count_status; # ����� ���� ������ �������� ��������� ������ ����������

        # ������� ������ ���������������, ��������� �� ���������� ���������
        my $count = hash($base_count_result, 'count');
        foreach my $cntk (keys %$count) {
            my $cnt             = $count->{$cntk};
            my $cnt_val         = ref($cnt->{value}) eq 'HASH' ? $cnt->{value} : $cnt->{value}[0];
            my $cnt_val_type    = uv2void($cnt_val->{type});
            my $cnt_err         = ref($cnt->{error}) eq 'HASH' ? $cnt->{error} : $cnt->{error}[0];
            my $cnt_err_code    = tv2int($cnt_err->{code});
            my $cnt_err_content = uv2void($cnt_err->{content});
            my $expires         = ref($cnt->{expires}) eq 'ARRAY' ? $cnt->{expires}[0] : $cnt->{expires};
            my $status          = ref($cnt->{status}) eq 'ARRAY' ? $cnt->{status}[0] : $cnt->{status};
            
            if ($cnt_val_type =~ /^STR|DIG$/i) { # ��������� �������������� (�������)
                push @summary, {
                        count   => sprintf("%s::%s", $base_count_name, $cntk),
                        pubdate => $pubdate,
                        expires => expire_calc(uv2void($expires)),
                        worktms => _tms(),
                        status  => uv2void($status) || 'ERROR',
                        errcode => $cnt_err_code,
                        errmsg  => $cnt_err_content,
                        type    => $cnt_val_type,
                        value   => uv2void($cnt_val->{content}),
                    };
            } elsif ($cnt_val_type =~ /^TAB$/i) {
                # ������������� ��������������
                my $cnt_val_rec = hash($cnt_val->{record});
                foreach my $rowk (keys %$cnt_val_rec) {
                    my $row = hash($cnt_val_rec, $rowk);
                    foreach my $colk (keys %$row) {
                        my $col = uv2void($row->{$colk});
                        push @summary, {
                                count   => sprintf("%s::%s::%s::%s",$base_count_name, $cntk,$rowk,$colk),
                                pubdate => $pubdate,
                                expires => expire_calc(uv2void($expires)),
                                worktms => _tms(),
                                status  => uv2void($status) || 'ERROR',
                                errcode => $cnt_err_code,
                                errmsg  => $cnt_err_content,
                                type    => is_flt($col) ? 'DIG' : 'STR',
                                value   => $col,
                            };
                    }
                    
                    
                }
            }
            
        }
    }
    #::debug Dumper(\@summary);
    
    # ��������� ��������� ��� �������� �� ������ -> �������
    my $xml = ag_prepare({
            name => uv2void(value($config => 'alertgrid/alertgridname')),
        }, \@summary);
    #::debug $xml;
    
    # ����������� ��� ���������
    my $transfertype = value($config, "alertgrid/agent/transfertype") || 'http';
    if ($transfertype =~ /local/i) {
        start "AlertGrid local agent starting";
        ($stt, $err) = ag_server({
                    dbfile  => $dbfile,
                    agentip => value($config, 'alertgrid/agent/ip'),
                },
                $xml
            );
    
        if ($stt) {
            finish DONE;
        } else {
            $self->status(FALSE);
            $self->message(ERROR);
            $self->error($err);
            finish ERROR;
        }
        
    } else { # http
        $self->_ag_remote_request(
                action  => "store",
                xml     => $xml,
                dbfile  => $dbfile,
            );
    }
    
    # ����� / �������
    my $rslt = $self->foutput("alertgrid", {
            dbfile  => $dbfile,
        });
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    $self->status;
}
sub rrdtool_create {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    
    start "RRDtool initialization";
    my $rrdtool = new App::MonM::RRDtool $self->opt('testmode') ? 1 : 0;
    if ($rrdtool->status) {
        finish DONE;
        
        # ��������� ������ ������������ ������ RRD
        my $rrdnode = node($config, "rrd");
        my $graphs = node($rrdnode, "graph");
        foreach my $k (keys(%$graphs)) {
            start "Creating RRD file for \"$k\" graph...";
            my $graph = hash($graphs, $k);
            unless (value($graph, 'enable')) {
                finish SKIPPED;
                next ;
            }
            $rrdtool->create(
                    type => lc(value($graph, 'type') || ''),
                    file => lc(value($graph, 'file') || ''),
                );
            if ($rrdtool->status) {
                finish DONE;
            } else {
                $self->status(FALSE);
                $self->message(ERROR);
                $self->error($rrdtool->error);
                finish ERROR;
            }
        }
    } else {
        $self->status(FALSE);
        $self->message(ERROR);
        $self->error($rrdtool->error);
        finish ERROR;
    }
    
    # ����� / �������
    my $rslt = $self->foutput("rrd", {
            #dbfile  => $dbfile,
        });
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    $self->status;
}
sub rrdtool_update {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;

    # DATA from STDIN or FILE. Default - error
    my $indata = "";
    if ($self->opt("stdin")) {
        $indata = _read_stdin();
    } elsif ($self->opt("input")) {
        my $fin = $self->opt("input");
        $indata = bload( $fin, 1 ) if -e $fin;
    }
    Encode::_utf8_on($indata);
    

    start "RRDtool initialization";
    my $rrdtool = new App::MonM::RRDtool $self->opt('testmode') ? 1 : 0;
    if ($rrdtool->status) {
        finish DONE;
        
        # ��������� ������ ������������ ������ RRD
        my $rrdnode = node($config, "rrd");
        my $graphs = node($rrdnode, "graph");
        foreach my $k (keys(%$graphs)) {
            start "Updating RRD files for \"$k\" graph...";
            my $graph = hash($graphs, $k);
            unless (value($graph, 'enable')) {
                finish SKIPPED;
                next ;
            }
            $rrdtool->update(
                    type => lc(value($graph, 'type') || ''),
                    file => lc(value($graph, 'file') || ''),
                    sources => hash($graph),
                    xml  => $indata,
                );
            if ($rrdtool->status) {
                finish DONE;
            } else {
                $self->status(FALSE);
                $self->message(ERROR);
                $self->error($rrdtool->error);
                finish ERROR;
            }
        }
        
    } else {
        $self->status(FALSE);
        $self->message(ERROR);
        $self->error($rrdtool->error);
        finish ERROR;
    }

    # ����� / �������
    my $rslt = $self->foutput("rrd", {
            #dbfile  => $dbfile,
        });
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    $self->status;
}
sub rrdtool_graph {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    
    start "RRDtool initialization";
    my $rrdtool = new App::MonM::RRDtool $self->opt('testmode') ? 1 : 0;
    if ($rrdtool->status) {
        finish DONE;
        
        # ��������� ������ ������������ ������ RRD
        my $rrdnode = node($config, "rrd");
        my $graphs = node($rrdnode, "graph");
        foreach my $k (keys(%$graphs)) {
            start "Plotting \"$k\" graph...";
            my $graph = hash($graphs, $k);
            unless (value($graph, 'enable')) {
                finish SKIPPED;
                next ;
            }
            $rrdtool->graph(
                    name => $k,
                    type => lc(value($graph, 'type') || ''),
                    file => lc(value($graph, 'file') || ''),
                    dir  => value($rrdnode, 'outputdirectory'),
                    mask => value($rrdnode, 'imagemask'),
                );
            if ($rrdtool->status) {
                finish DONE;
            } else {
                $self->status(FALSE);
                $self->message(ERROR);
                $self->error($rrdtool->error);
                finish ERROR;
            }
        }
        
    } else {
        $self->status(FALSE);
        $self->message(ERROR);
        $self->error($rrdtool->error);
        finish ERROR;
    }

    # ����� / �������
    my $rslt = $self->foutput("rrd", {
            #dbfile  => $dbfile,
        });
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    $self->status;
}
sub rrdtool_index {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;

    # !!! ���� ������� ������������ ���������� ����� ����� �������� �������� !!!
    # !!!    � ���� ������� � ������ �� �� RRDtool.pm �����                  !!!
    
    my $tpl_default = catfile(sharedir(), 'monm', 'www', 'rrd.tpl');
    my $rrdnode = node($config, "rrd");
    my $graphs  = node($rrdnode, "graph");
    my $odir    = value($rrdnode, 'outputdirectory');
    my $mask    = value($rrdnode, 'imagemask') || App::MonM::RRDtool::MASK();
    my $idx_file    = value($rrdnode, 'indexfile') || '';
    my $tpl_file    = value($rrdnode, 'indextemplatefile') || 'rrd.tpl';
    my $tpl_uri     = value($rrdnode, 'indextemplateuri') || '';
    my $gtypes = App::MonM::RRDtool::GTYPES();
    my ($volume,$dir,$fakefile) = splitpath(catfile($odir, 'fake.txt'));
    my $path = File::Spec->catpath( $volume, $dir, '' );
    
    # ���������� ������
    my $tpl;
    if ($tpl_file && -e $tpl_file) {
        $tpl = new TemplateM(-file => $tpl_file, -asfile => 1, -utf8 => 1, );
    } elsif ($tpl_uri) {
        $tpl = new TemplateM(-file => $tpl_uri, -utf8 => 1, );
    } elsif ($tpl_default && -e $tpl_default) {
        $tpl = new TemplateM(-file => $tpl_default, -asfile => 1, -utf8 => 1, );
    } else {
        $tpl = new TemplateM(-template => "Undefined template file.\n\nPlease edit IndexTemplateFile or IndexTemplateURI configuration parameters", -utf8 => 1, );
    }
    $tpl->stash(
            expires => dtf("%w, %DD %MON %YYYY %hh:%mm:%ss %G",time()+300,1),
            pubdate => dtf("%w, %DD %MON %YYYY %hh:%mm:%ss %G",time(),1),
        );

    my @skeys = ();
    
    # ������� ������ (������� ������ MINI ������)
    my $index_box = $tpl->start('index');
    foreach my $rrdkey ( sort {$a cmp $b } keys %$graphs ) {
        my $rrd = hash($graphs, $rrdkey);
        next unless value($rrd, 'enable');
        my $type = lc(value($rrd, 'type') || '');
        push @skeys, $rrdkey;
        my $mini = dformat($mask, { EXT => "png", TYPE => $type, KEY => $rrdkey, GTYPE => "mini" });
        #my $gimage = value($rrd, 'image') || '';
        #my $graph = array($rrd,"graph"); $graph->[0] = hash($rrd,"graph") unless $graph->[0];
        #$image = catfile($odir, );
        
        $index_box->loop(
                image => $mini,
                path  => $path,
                name  => $rrdkey,
            );        
    }    
    $index_box->finish;
    
    # ������� ����� ��������
    my $graphs_box = $tpl->start('graphs');
    foreach my $k (@skeys) {
        my $type = lc(value($graphs, $k, 'type') || '');
        my @ikeys = grep { $_ ne 'mini' } @$gtypes;
        $graphs_box->loop(
            title => $k,
        );
        my $img_box = $graphs_box->start('images');
        foreach my $j (@ikeys) {
            my $image = dformat($mask, { EXT => "png", TYPE => $type, KEY => $k, GTYPE => $j });
            $img_box->loop(
                image => $image,
                path  => $path,
            );
        }
        $img_box->finish;
    }
    $graphs_box->finish;
    
    # ������ ���������� � �������� ���� $idx_file
    bsave( $idx_file ? $idx_file : catfile($odir, 'index.html'), $tpl->output, 1 );

    # ����� / �������
    my $rslt = $self->foutput("rrd", {});
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    $self->status;
}

sub foutput { # ���������� ������ � ��������� (�� ����) ������� � �������� ���������� �� �����
    my $self = shift;
    my $name = shift || 'monm'; # ��� ������
    my $base = shift || {}; # ������� ��������
    my $data = shift || []; # ������
    my $head = shift || []; # ��������� (������� ������)
    my $doc  = '';
    
    # ��������� ���������� ���� (�������� ���������)
    unless ($base && ref($base) eq 'HASH') {
        carp("Incorrect base attributes");
        $base = {};
    }
    $base->{status}     = $self->status,
    $base->{message}    = $self->message,
    $base->{error}      = $self->error;
    $base->{pubdate}    = dtf("%w, %DD %MON %YYYY %hh:%mm:%ss %G",time(),1),
    $base->{worktms}    = $self->ctkx->c->tms,
    
    # ���������� ���
    my $type = lc(uv2null($self->opt('format')));
    $type = "default" unless grep {$_ eq $type} @{(FORMATS)};
    #debug "TYPE: $type";
    
    # ���������������� �������
    if ($type eq 'xml') {
        my $output = {}; foreach (keys %$base) { $output->{$_} = [$base->{$_}] };
        $output->{head} = [{ th => $head }];
        $output->{data} = [{ td => $data }];
        $doc = XMLout( $output,
                RootName => $name,
                XMLDecl  => XMLDECL,
            );
        Encode::_utf8_on($doc) if $self->opt("utf8");
    } elsif ($type eq 'json') {
        my $output = {}; foreach (keys %$base) { $output->{$_} = $base->{$_} };
        $output->{head} = { th => $head };
        $output->{data} = { td => $data };
        $doc = to_json( $output,
                {
                    utf8 => $self->opt('utf8') ? 0 : 1,
                }
            );
        Encode::_utf8_on($doc) if $self->opt("utf8");
    } elsif ($type eq 'yaml' or $type eq 'yml') {
        my $output = {}; foreach (keys %$base) { $output->{$_} = $base->{$_} };
        $output->{head} = { th => $head };
        $output->{data} = { td => $data };
        $doc = Dump($output);
        Encode::_utf8_on($doc) if $self->opt("utf8");
    } elsif ($type eq 'dump' or $type eq 'dmp') {
        my $output = {}; foreach (keys %$base) { $output->{$_} = $base->{$_} };
        $output->{head} = { th => $head };
        $output->{data} = { td => $data };
        $doc = Dumper($output)
    } elsif ($type eq 'none') {
        return VOID;
    } else { # } elsif ($type eq 'text' or $type eq 'txt') { # �� �������� - ��������� ����� ������
        my $bdoc = _get_table($base);
        my %headers = ();
        my @headerc = ();
        my $i = 0;
        # ��������� ������
        foreach (@$head) {
            $headerc[$i] = length($_) || 1; # �������
            $headers{$_} = $i;              # ���� -> [������]
            $i++;
        }
        foreach my $row (@$data) {
            $i=0;
            foreach my $col (@$row) {
                $headerc[$i] = length($col) if defined($col) && length($col) > $headerc[$i];
                $i++
            }
        }
        # ������������ ����������
        my $tbl = Text::SimpleTable->new(map {$_ = [$headerc[$headers{$_}],$_]} @$head) if @$head;
        foreach my $row (@$data) {
            my @tmp = ();
            foreach my $col (@$row) { push @tmp, (defined($col) ? $col : '') }
            $tbl->row(@tmp);
        }
        if (@$data) {
            $doc = sprintf("%s:\n%sDATA:\n%s__END__", uc($name), $bdoc, $tbl->draw() || '');
        } else {
            $doc = sprintf("%s:\n%s__END__", uc($name), $bdoc);
        }
        Encode::_utf8_on($doc) if $self->opt("utf8");
    }
    
    # ������������ ������
    my $file = $self->opt("output");
    if ($file) { # ����� � ����
        bsave($file, $doc, $self->opt("utf8") ? 1 : 0);
    } else { # ����� � STDOUT ���� �� ���������� �����
        # binmode STDOUT, ':raw:utf8'; # see new();
        print STDOUT $doc unless $self->ctkx->c->debugmode;
    }
    return $doc;
}
sub _ag_remote_request { # ���������� ��������� ��������� ������
    my $self = shift;
    my %d = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    my $xml = $d{xml} || '';
    
    # ��������� ������ �� HTTP
    #
    # 1. ����������� ������������ �������: HTTP �������� � ������ ����������� � ������ �����
    # 2. ����������� ������� � ������� ��������� ��������� ������� GET check
    # 3. ������������ ��� ������ �� ������ POST (� ���������� ��� default)
    # 4. ����������� ��������� �� ������ � ������������ ������!

    # ��������� ���������� HTTP
    my $http_data = {};
    my $http_attr = {};
        
    $http_data = hash($config => 'alertgrid/agent/http');
    if (keys %$http_data) {
        $http_attr = _get_attr($http_data);
    } else {
        debug "Incorrect configuration section <HTTP>";
    }
    #debug sprintf("ATTR: %s", Dumper($http_attr));

    # ������ ����
    my $cookie_jar = undef;
    if (value($http_data, 'cookieenable')) {
        start "Setting Cookie";
        my %cookie;
        my $hhc = hash($http_data, 'cookie');
        $cookie{file} = catfile($c->datadir, sprintf("%s.cj", $c->prefix));
        $cookie{$_} = value($hhc, $_) for (keys %$hhc);
        $cookie_jar = new HTTP::Cookies(%cookie);
        finish DONE;
    }

    # �������������� ������ ������
    start "Preparing data for transfering";

    # �������������� �����
    my %uaopt;
    my $hhua = hash($http_data, 'ua');
    $uaopt{agent} = __PACKAGE__."/".$VERSION;
    $uaopt{timeout} = $self->opt("timeout") || value($hhua, "timeout") || AG_TIMEOUT;
    $uaopt{cookie_jar} = $cookie_jar if $cookie_jar;
    for (keys %$hhua) {
        my $uas = node($hhua, $_);
        $uaopt{$_} = array($uas) if is_array($uas);
        $uaopt{$_} = value($uas) if is_value($uas);
        $uaopt{$_} = hash($uas) if is_hash($uas) && $_ ne 'header';
    }
    my $ua = new LWP::UserAgent(%uaopt); 
        
    # ������� ������ ��� ������
    my $hhh = hash($hhua, 'header');
    $ua->default_header($_, value($hhh, $_)) for (keys %$hhh);

    # �������������� �������� �������
    my $method = uc($self->opt("method") || value($http_data, 'method') || "GET");
    my $url = $self->opt("url") || value($http_data, 'uri') || value($http_data, 'url') || '';
    my $login = $self->opt("user") || value($http_data, 'user') || value($http_data, 'login') || '';
    my $passwd = $self->opt("password") || value($http_data, 'password') || '';


    # �������������� URI-Object
    my $uri = new URI( $url );
    my $uri_test = $uri->clone;
    
    # �������������� ������ URI
    my %qform = $uri->query_form;
    $qform{action} = $d{action} || '';
    $qform{dbfile} = $d{dbfile} if value($http_data, 'senddbfile');
    $qform{data} = $xml if $xml && $method eq 'GET';
    $uri->query_form( %qform );

    # �������������� �������� URI
    my %qform_test = $uri_test->query_form;
    $qform_test{action} = 'check';
    $uri_test->query_form( %qform_test);


    # �������������� ������ ��� ������
    $ua->add_handler( request_prepare => sub { 
            my($req, $ua, $h) = @_;
            $req->authorization_basic( $login, $passwd );
            return $req;
        } ) if $login;
    my $req = new HTTP::Request(uc($method), $uri);
    $req->header('Content-Type', ($method eq "POST") ? "application/x-www-form-urlencoded" : "text/plain") unless $req->header('Content-Type');
        
    if ($method eq "POST") {
        my $req_content = '';
        my $dreq = $uri->query;
        $req_content = $dreq;
        $req_content .= '&data='.$xml if $xml;
        my $req_content_length = length $req_content;
        $req->header('Content-Length', $req_content_length) unless $req->header('Content-Length'); # Not really needed
        $req->content($req_content) if defined($req_content) && $req_content ne "";
    }
        
    finish DONE; # �������������� ������ ������

    # ��������� �������� ������
    start "Sending check request";
    {
        my $req_test = new HTTP::Request('GET', $uri_test);
        my $res = $ua->request($req_test);
        if ($res->is_success) {
            my $testdata = $res->decoded_content;
            if ($testdata && length($testdata) && $testdata =~ /^OK/i) {
                finish DONE;
            } else {
                $self->status(FALSE);
                $self->message(ERROR);
                $self->error($testdata);
                finish ERROR;
            }
        } else {
            $self->status(FALSE);
            $self->message(ERROR);
            $self->error($res->status_line);
            finish ERROR;
        }
    }


    # ��������� �������� ������ � ������ ����������� ���������
    start "Sending main request";
    my $fetchdata = '';
    {
        if ($self->status) {
            my $res = $ua->request($req);
            if ($res->is_success) {
                $fetchdata = $res->decoded_content;
                if ($fetchdata && length($fetchdata) && $fetchdata =~ /^OK/i) {
                    finish DONE;
                } else {
                    $self->status(FALSE);
                    $self->message(ERROR);
                    $self->error($fetchdata);
                    $fetchdata = '';
                    finish ERROR;
                }
            } else {
                $self->status(FALSE);
                $self->message(ERROR);
                $self->error($res->status_line);
                finish ERROR;
            }
        } else {
            finish SKIPPED;
        }
    }

    return $fetchdata;
}

sub _node2anode { # ��������� ���� � ������ ���
    my $n = shift;
    return [] unless $n && ref($n) =~ /ARRAY|HASH/;
    return [$n] if ref($n) eq 'HASH';
    return $n;
}
sub _get_attr { # ��������� ������������� �������� HTTP � ������ ������
    my $in = shift;
    my $attr = array($in => "set");
    my %attrs;
    foreach (@$attr) {
        $attrs{$1} = $2 if $_ =~ /^\s*(\S+)\s+(.+)$/;
    }
    #if ($in && ref($in) eq 'HASH') { $in->{attr} = {%attrs} } 
    return {%attrs};
}
sub _read_stdin {
    return scalar(do { local $/; <STDIN> })
}
sub _get_table {
    my $hin = shift || {};
    my $limit = $SCREEN_W || SCREENWIDTH;
    
    # ��������� ������
    my @th = sort {$a cmp $b} keys %$hin;
    my $max_h = 0;
    my $max_d = 0;
    foreach (@th) {
        my $lh = length($_);
        my $ld = _length($hin->{$_});
        $max_h = $lh if $max_h < $lh;
        $max_d = $ld if ($max_d < $ld) && ($ld < $limit);
    }
    my $tbl = Text::SimpleTable->new([$max_h, "NAME"],[$max_d, "VALUE"]);
    foreach (@th) { $tbl->row($_, uv2null($hin->{$_})) }
    return $tbl->draw() || '';
}
sub _length { # ��������� ����� �������������� ��������
    my $s = shift;
    return 0 unless defined $s;
    my $m = 0;
    foreach (split(/\r*\n/, $s)) {
        $m = length($_) if $m < length($_);
    }
    return $m;
}
sub _show_http_report {
    my $r = shift;
    my $meth = shift || "GET";
    debug "-----BEGIN HTTP TRANSACTION-----";
    debug $meth, " ", $r->request->uri->as_string;
    debug $r->request->headers_as_string;
    debug $r->status_line;
    debug $r->headers_as_string;
    debug "-----END HTTP TRANSACTION-----";
}
sub _show_result_data {
    my $ls = shift;
    my $u8 = shift;
    
    if ($u8) {
        debug "-----BEGIN RESULT UNIDECODED DATA-----";
        debug unidecode($$ls);
        debug "-----END RESULT UNIDECODED DATA-----";
    } else {
        debug "-----BEGIN RESULT DATA-----";
        debug $$ls;
        debug "-----END RESULT DATA-----";
    }
}
sub _fbytes { # From lwp_download
    my $n = int(shift);
    if ($n >= 1024 * 1024) {
        return sprintf "%.3g MB", $n / (1024.0 * 1024);
    } elsif ($n >= 1024) {
        return sprintf "%.3g kB", $n / 1024.0;
    }
    return "$n bytes";
}
sub _fduration { # From lwp_download
    use integer;
    my $secs = int(shift);
    my $hours = $secs / (60*60);
    $secs -= $hours * 60*60;
    my $mins = $secs / 60;
    $secs %= 60;
    if ($hours) {
        return "$hours hours $mins minutes";
    } elsif ($mins >= 2) {
        return "$mins minutes";
    } else {
        $secs += $mins * 60;
        return "$secs seconds";
    }
}
sub _tms { # BackWard for CTK::tms
    my $code = main->can("tms");
    return &$code() if ref($code) eq 'CODE';
    return "[$$] {TimeStamp: ".sprintf("%+.*f",4, time()-$^T)." sec}"
}

1;

__END__

# See lwp-download example. 
#sub get_basic_credentials {
#    return("user", "pasword")
#}
