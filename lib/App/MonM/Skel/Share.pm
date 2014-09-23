package App::MonM::Skel::Share; # $Id: Share.pm 9 2014-09-20 20:28:46Z abalama $
use strict;

use CTK::Util qw/ :BASE /;

use constant SIGNATURE => "share";

use vars qw($VERSION);
$VERSION = '1.00';

sub build { # Процесс сборки
    my $self = shift;
    $self->maybe::next::method();
    return 1;
}
sub dirs { # Список директорий и прав доступа к каждой из них
    my $self = shift;    
    $self->{subdirs}{(SIGNATURE)} = [
        {
            path => 'foo',
            mode => 0755,
        },
        {
            path => 'bar',
            mode => 0755,
        },
        {
            path => '%BAZ%',
            mode => 0755,
        },
        
    ];
    $self->maybe::next::method();
    return 1;
}
sub pool { # Бассеин с разделенными multipart файламми
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
Name: monm.cgi
File: monm.cgi
Mode: 711
Type: Windows

For windows
-----END FILE-----

-----BEGIN FILE-----
Name: monm.cgi
File: monm.cgi
Mode: 711
Type: Unix

For Unix
-----END FILE-----