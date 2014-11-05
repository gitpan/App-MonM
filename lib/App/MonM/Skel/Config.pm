package App::MonM::Skel::Config; # $Id: Config.pm 18 2014-10-02 14:49:45Z abalama $
use strict;

use CTK::Util qw/ :BASE /;

use constant SIGNATURE => "config";

use vars qw($VERSION);
$VERSION = '1.01';

sub build { # ������� ������
    my $self = shift;

    my $rplc = $self->{rplc};
    $rplc->{FOO} = "foo";
    $rplc->{BAR} = "bar";
    $rplc->{BAZ} = "baz";
    
    $self->maybe::next::method();
    return 1;
}
sub dirs { # ������ ���������� � ���� ������� � ������ �� ���
    my $self = shift;    
    $self->{subdirs}{(SIGNATURE)} = [
        {
            path => 'extra',
            mode => 0755,
        },
        {
            path => 'conf.d',
            mode => 0755,
        },
    ];
    $self->maybe::next::method();
    return 1;
}
sub pool { # ������� � ������������ multipart ��������
    my $self = shift;
    my $pos =  tell DATA;
    my $data = scalar(do { local $/; <DATA> });
    seek DATA, $pos, 0;
    $self->{pools}{(SIGNATURE)} = $data;
    $self->maybe::next::method();
    return 1;
}

1;
__DATA__

-----BEGIN FILE-----
Name: monm.conf
File: monm.conf
Mode: 644

# %DOLLAR%Id%DOLLAR%
# GENERATED: %GENERATED%
#
# See Config::General for details
#

# Activate or deactivate the logging: on/off (yes/no)
# LogEnable off
LogEnable   on

# debug level: debug, info, notice, warning, error, crit, alert, emerg, fatal, except
# LogLevel debug
LogLevel warning

Include extra/*.conf
Include conf.d/*.conf

-----END FILE-----

-----BEGIN FILE-----
Name: sendmail.conf
File: extra/sendmail.conf
Mode: 644

<SendMail>
    To          to@example.com
    Cc          cc@example.com
    From        from@example.com
    Type        text/plain
    #Sendmail   /usr/sbin/sendmail
    #Flags      -t
    SMTP        192.168.0.1
</SendMail>
-----END FILE-----

-----BEGIN FILE-----
Name: checkit.conf
File: extra/checkit.conf
Mode: 644

# GateWay for sending SMS
SMSGW "sendalertsms -s SIDNAME -u USER -p PASSWORD -q "SELECT SMS_FUNCTION('[PHONE]', '[MESSAGE]') FROM DUAL" [PHONE]"

-----END FILE-----

-----BEGIN FILE-----
Name: checkit-foo.conf
File: conf.d/checkit-foo.conf
Mode: 644

#
# See checkit-foo.conf.sample and README for details
#
<Checkit "foo">
    Enable      yes
    URL         http://www.example.com
    Target      code
    IsTrue      200
</Checkit>
-----END FILE-----

-----BEGIN FILE-----
Name: checkit-foo.conf.sample
File: conf.d/checkit-foo.conf.sample
Mode: 644

#
# See README for details
#
<Checkit "foo">
    Enable      yes
    URL         http://www.example.com
    Target      code
    IsTrue      200
</Checkit>
-----END FILE-----

-----BEGIN FILE-----
Name: checkit-foo.conf.sample
File: conf.d/checkit-foo.conf.sample
Mode: 644
Type: Windows

<Checkit "foo">
    # ������� ��� �������� �������. �� ��������� ������� ��������!
    # Enable    no
    Enable      yes

    # ����������� "��� ����� �����!"
    # IsFalse   !!perl/regexp (?i-xsm:^\s*(error|fault|no)) # ������������ �� ���������
    # IsFalse   ERROR
    
    # ����������� "��� ����� ������!"
    # IsTrue    !!perl/regexp (?i-xsm:^\s*(ok|yes)) # ������������ �� ���������
    # IsTrue    OK
    # IsTrue    Ok.

    # ������� ���������� ��������.
    # OrderBy   true, false # ������������ �� ���������
    # OrderBy   ASC # ������ ����������� �������
    # OrderBy   ASC

    # �������� ������� ����������. ��� ���� ������� ����������� ������� 
    # ������� false � ����� true, � ������ ���� �� ������ ������� true
    # OrderBy   false, true
    # OrderBy   DESC # ������ ����������� �������

    # ��� ������� ��������� ����������.
    # Type      http # ������������ �� ���������
    # Type      dbi
    # Type      oracle
    # Type      command
    
    ###################################
    ## ������ ��� �������� ���� HTTP ##
    ###################################
    
    # ����� ��� HTTP ������� 
    # URL       http://user:password@www.example.com
    URL         http://www.example.com
    
    # ����� HTTP. GET, POST, PUT, HEAD, OPTIONS, PATCH, DELETE, TRACE, CONNECT
    # Method    GET # ������������ �� ���������
    # Method    POST
    # Method    HEAD
    # Method    OPTIONS
    
    # ������ �������
    # Target    content # ����������� ����������. ������������ �� ���������
    # Target    code # ����������� HTTP ��� ������.
    # Target    status # ����������� HTTP ������ ������ (status line).

    ##################################
    ## ������ ��� �������� ���� DBI ##
    ##################################
    
    DSN         DBI:mysql:database=DATABASE;host=HOSTNAME
    # SQL       "SELECT 'OK' AS OK FROM DUAL" # ������������ �� ���������
    User        USER
    Password    PASSWORD
    # Connect_to    5 # ������� �� �������
    # Request_to    60 # ������� �� ���������� �������
    
    # ��������. �� ��������� ������������ ������ PrintError 0
    #<ATTR>
    #  Mysql_enable_utf8    1
    #  PrintError           0
    #</ATTR>

    # ����������� ����������������� ���������
    # Set PrintError  0
    
    #####################################
    ## ������ ��� �������� ���� ORACLE ##
    #####################################
    
    SID         SIDNAME # SID �������� ������ �� ������������ ���� tnsnames.sql. �� ��������� TEST
    # SQL       "SELECT 'OK' AS OK FROM DUAL" # ������������ �� ���������
    User        USER
    Password    PASSWORD
    # Connect_to    5 # ������� �� �������
    # Request_to    60 # ������� �� ���������� �������
    
    # ��������. �� ��������� ������������ ������ PrintError 0
    #<ATTR>
    #  PrintError           0
    #</ATTR>

    # ����������� ����������������� ���������
    # Set PrintError  0
    
    ######################################
    ## ������ ��� �������� ���� COMMAND ##
    ######################################
    
    Command     "ls -la" # ������� ������� ����� ��������� �� ������� ��� App::MonM �������!
    IsTrue      !!perl/regexp (?i-xsm:README)

    # ��������.
    # �������� ����������� �� ��������� �������� � True �� False � ������� � ������ 
    # �������� �� ��������� (�������) ������.
    <Triggers>
        # ������ ������� ����������� ����� ��� �������� ����� ������������ �������:
        # ����: MONM CHECKIT REPORT
        # ���������: ���� ��������� �������� � ������������
        # emailalert    foo@example.com
        # emailalert    bar@example.com
        # emailalert    baz@example.com

        # ������ ������� ��������� ��� �������� ��������� � ������� �������� ����������. ������
        # ������� ���������� � ������������� ��������� (DEF) ��� �������� ����� (+)
        # smsalert      11231230001
        # smsalert      11231230002
        # smsalert      11231230003

        # ������ ������, ������� ����� ��������� �� ������������ ��������
        # �������� �����������:
        #   [SUBJECT] -- ����
        #   [MESSAGE] -- ���������
        # command       "mycommand1 \"[SUBJECT]\" \"[MESSAGE]\""
        # command       "mycommand2 \"[MESSAGE]\""
        # command       "mycommand3"
    </Triggers>

    # ��������� ��� ����� SMS. ���� ������ ����������� �������, �� �� ��������� �����
    # �������������� ����������� �� ����� extra/checkit.conf
    # �������� �����������:
    #   [PHONE]   -- ����� ��������
    #   [SUBJECT] -- ����
    #   [MESSAGE] -- ���������
    # SMSGW "sendalertsms "[NUMBER]" "[SUBJECT]" "[MESSAGE]""

</Checkit>
-----END FILE-----

-----BEGIN FILE-----
Name: dbi-foo.conf.sample
File: conf.d/dbi-foo.conf.sample
Mode: 644

<DBI foo>
    DSN     "DBI:mysql:database=NAME;host=HOST"
    #SID    TEST
    SQL     SELECT SYSDATE() FROM DUAL
    User                    USER
    Password                PASSWORD
    Connect_to              5
    Request_to              60
    Set mysql_enable_utf8   1
    Set PrintError          0
</DBI>
-----END FILE-----

-----BEGIN FILE-----
Name: http-foo.conf.sample
File: conf.d/http-foo.conf.sample
Mode: 644

<HTTP foo>
    CookieEnable    yes
    Method          POST
    URL             "http://www.example.com"
    #Login          USER
    #Password       PASSWORD
    UTF8            yes
    Data            "foo=bar&baz=qux"

    <Cookie>
      Autosave      1
      #File	data/test.cj
    </Cookie>
    <UA>
      <Header>
        Accept-Language     ru
        Cache-Control       no-cache
      </Header>
      <SSL_OPTS>
        verify_hostname		0
      </SSL_OPTS>

      Protocols_Allowed     http
      Protocols_Allowed     https # Required Crypt::SSLeay

      Requests_Redirectable GET
      Requests_Redirectable HEAD
      Requests_Redirectable POST

      Agent         "MonM/1.0"
      Max_Redirect  10
      Keep_Alive    1
      Env_Proxy     1
      Timeout       180
    </UA>
</HTTP>
-----END FILE-----