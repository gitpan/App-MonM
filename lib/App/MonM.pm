package App::MonM; # $Id: MonM.pm 12 2014-09-23 13:16:47Z abalama $
use strict;

=head1 NAME

App::MonM - Simple Monitoring Tools

=head1 VERSION

Version 1.00

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
$VERSION = '1.00';

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

# libwww
use URI;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Cookies;

use App::MonM::Checkit;

use constant {
    SCREENSTEP  => 9, # indent
    SCREENWIDTH => 80 - 9, # = <width> - <indent on test-status >
    FORMATS     => [qw/ yaml yml xml json text txt dump dmp none /],
    XMLDECL     => '<?xml version="1.0" encoding="utf-8"?>',
    
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
    
    # Подготовка каналов
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

    # Вывод
    my $rslt = $self->foutput("void");

    # Отладка
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

    # Вывод
    my $rslt = $self->foutput("test", {
            logdir      => uv2null($c->logdir),
            logfile     => uv2null($c->logfile),
            confdir     => uv2null($c->confdir),
            conffile    => uv2null($c->cfgfile),
            datadir     => uv2null($c->datadir),
            voidfile    => uv2null($c->voidfile),
        }, \@rsltd, \@rslth);

    # Отладка
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

    # Статические переменные
    my $dbi_data = {};
    my $dbi_attr = {};
    
    # Получение имени секции & чтение параметров секции
    my $name = $data{args} && $data{args}[0] ? $data{args}[0] : '';
    if ($name) {
        # Принимаем данные хоста если они заданы
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
    if ($sid) { # SID в параметре на входе или в конфиге
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

    # Результат всей операции
    unless ($connect_status && $execute_status && $fetch_status) {
        $self->status(FALSE);
        $self->message(ERROR);
    }
    
    # Вывод
    $rslt = $self->foutput("dbi", {
            connect     => $connect_message,
            execute     => $execute_message,
            fetch       => $fetch_message,
            disconnect  => $disconnect_message,
        }, \@rsltd, \@rslth);
    
    # Отладка
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    
    $self->status;
}
sub http {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;

    # Статические переменные
    my $file = $self->opt("file"); # Файл для принятого коннтента
    my $http_data = {};
    my $http_attr = {};
    
    # Получение имени секции & чтение параметров секции
    my $name = $data{args} && $data{args}[0] ? $data{args}[0] : '';
    if ($name) {
        # Принимаем данные хоста если они заданы
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
    
    # Корректировка utf8 признака
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

    # Ставим куку
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

    # Подготавливаем данные вызова
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
    }
    my $ua = new LWP::UserAgent(%uaopt); 
    
    # Готовим хидеры для агента
    my $hhh = hash($hhua, 'header');
    $ua->default_header($_, value($hhh, $_)) for (keys %$hhh);
    
    # Подготавливаем коннект
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
    
    # Подготавливаем данные для вызова
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
    
    # Выполняем запрос
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
    # Получение ответа. Сводная информация
    my %ret; # Результативный хэш для данных анонимных процедур
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
    
    # Получаем данные
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

    # Вывод
    my $rslt = $self->foutput("http", \%ret);

    # Отладка
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    
    $self->status;
}
sub checkit {
    my $self = shift;
    my %data = @_;
    my $c = $self->ctkx->c;
    my $config = $c->config;
    my $name = $data{args} && $data{args}[0] ? $data{args}[0] : ''; # Имя счетчика
    my $ymlfile = catfile($c->datadir,sprintf($data{ymlfile}, "")); # Значение по умолчанию
    my $chreq   = 0;    # Флаг того что что-то поменялось!
    my @actions;        # Инициализируем очередь для триггера
    my @tabled;         # Итоговая таблица (данные)
    my @trigd;          # Итоговая таблица выполнения триггеров (данные)
    my %ret; # Результативный хэш
   
    # Получение счетчиков
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
    
    # Получаем файл YAML
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
    
    # Непосредственно операции над счетчиками
    $c->log_debug("Start processing counts");
    my $pfx = " " x 3;
    foreach my $nc (sort {$a cmp $b} @clist) {
        start "Checking \"$nc\"";
        my $message = '';
        my $count = hash($counts_node,$nc);
        my $ydata = ($yaml_in->{$nc} && ref($yaml_in->{$nc}) eq 'ARRAY') ? $yaml_in->{$nc} : []; # Получаем статистику из файла YAML
        my ($status, $error) = readcount($count); # Выполнение и получение статуса выполнения операции

        # Корректируем входные данные
        my @newydata = @$ydata;
        my $corr = defined($newydata[0]) ? $newydata[0] : 0;
        $newydata[0] = defined($newydata[1]) ? $newydata[1] : 0;
        $newydata[1] = defined($newydata[2]) ? $newydata[2] : 0;
        $newydata[2] = ($status && $status eq 'OK') ? 1 : 0;
        
        # Данные отличаются? Возводим флаг!
        $chreq = 1 if (join("",@$ydata) ne join("",@newydata));

        # Создаем подструктуру для дальнейшей записи
        $yaml_out->{$nc} = [@newydata];
        
        # Выполняем анализ данных и получаем суммарный статус для счетчика
        if (checkcount($corr,@newydata)) { # Должен сработать триггер!!
            $message = sprintf("%s: Available %s [%s]", ($status eq 'OK' ? 'OK' : 'PROBLEM'), $nc, join("-",$corr,@newydata));
            # Добавляем запрос в очередь для триггера
            push @actions, {
                count       => $nc,
                countdata   => $count,
                message     => $message,
            };
        }

        # Результат счетчика
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
    
    # Записываем файл если хотябы что-то но поменялось
    if ($chreq) {
        try { YAML::Tiny::DumpFile($ymlfile, $yaml_out) } catch {
            $self->error("YAML::Tiny write error: $_");
            debug $self->lasterror;
            $c->log_error($self->lasterror);
        };
        CTK::carp("YAML::Tiny write error. Please check permissions for \"$ymlfile\"") unless -e $ymlfile;
    }

    # Выполняем очередь триггера и возвращение результата
    my $trigres = trigger($config, @actions);
    @trigd = @$trigres if $trigres && ref($trigres) eq 'ARRAY';

    # Непосредственно данные
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
    
    # Вывод & Отладка
    my $rslt = $self->foutput("checkit", \%ret, \@tabled, [qw(COUNT STATUS MESSAGE)]);
    _show_result_data(\$rslt, $self->opt("utf8")) if $self->opt('verbose');
    
    $self->status;
}
sub foutput { # Возвращает данные в выбранном (по типу) формате и отправка результата на выход
    my $self = shift;
    my $name = shift || 'monm'; # Имя секции
    my $base = shift || {}; # Базовые атрибуты
    my $data = shift || []; # Данные
    my $head = shift || []; # Заголовки (линйный массив)
    my $doc  = '';
    
    # формируем корректную базу (основные параметры)
    unless ($base && ref($base) eq 'HASH') {
        carp("Incorrect base attributes");
        $base = {};
    }
    $base->{status}     = $self->status,
    $base->{message}    = $self->message,
    $base->{error}      = $self->error;
    $base->{pubdate}    = dtf("%w, %DD %MON %YYYY %hh:%mm:%ss %G",time(),1),
    $base->{worktms}    = $self->ctkx->c->tms,
    
    # Определяем тип
    my $type = lc(uv2null($self->opt('format')));
    $type = "default" unless grep {$_ eq $type} @{(FORMATS)};
    #debug "TYPE: $type";
    
    # Непосредственный перевод
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
        my $output = {}; foreach (keys %$base) { $output->{$_} = [$base->{$_}] };
        $output->{head} = [{ th => $head }];
        $output->{data} = [{ td => $data }];
        $doc = to_json( $output,
                {
                    utf8 => $self->opt('utf8') ? 0 : 1,
                }
            );
        Encode::_utf8_on($doc) if $self->opt("utf8");
    } elsif ($type eq 'yaml' or $type eq 'yml') {
        $doc = Dump($base, $head, $data);
        Encode::_utf8_on($doc) if $self->opt("utf8");
    } elsif ($type eq 'dump' or $type eq 'dmp') {
        $doc = Dumper($base, $head, $data)
    } elsif ($type eq 'none') {
        return VOID;
    } else { # } elsif ($type eq 'text' or $type eq 'txt') { # По умочанию - текстовый вывод данных
        my $bdoc = _get_table($base);
        my %headers = ();
        my @headerc = ();
        my $i = 0;
        # максимумы данных
        foreach (@$head) {
            $headerc[$i] = length($_) || 1; # Счетчик
            $headers{$_} = $i;              # КЛЮЧ -> [индекс]
            $i++;
        }
        foreach my $row (@$data) {
            $i=0;
            foreach my $col (@$row) {
                $headerc[$i] = length($col) if defined($col) && length($col) > $headerc[$i];
                $i++
            }
        }
        # Формирование результата
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
    
    # Формирование вывода
    my $file = $self->opt("output");
    if ($file) { # Пишем в файл
        bsave($file, $doc, $self->opt("utf8") ? 1 : 0);
    } else { # Пишем в STDOUT если не отладочный режим
        # binmode STDOUT, ':raw:utf8'; # see new();
        print STDOUT $doc unless $self->ctkx->c->debugmode;
    }
    return $doc;
}

sub _node2anode { # Переводит ноду в массив нод
    my $n = shift;
    return [] unless $n && ref($n) =~ /ARRAY|HASH/;
    return [$n] if ref($n) eq 'HASH';
    return $n;
}
sub _get_attr {
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
    
    # максимумы данных
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
sub _length { # Вычисляет длину многострочного контента
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

1;

__END__

# See lwp-download example. 
#sub get_basic_credentials {
#    return("user", "pasword")
#}
