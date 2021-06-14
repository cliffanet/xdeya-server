package CUser::Jump;

use Clib::strict8;

sub _inf {
    my $jmp = shift() || return;
    my $inf = json2data($jmp->{data}) || return;
    
    foreach my $p ($inf->{beg}, $inf->{cnp}, $inf->{end}) {
        $p->{gpsok} = $p->{flags} & 0x0001 ? 1 : 0;
        $inf->{center} ||= $p if $p->{gpsok};
    }
    
    return $inf;
}

sub byId {
    sqlGet(jump => shift());
}

sub _root :
        ParamCodeUInt(\&CUser::Device::byIdMy)
        ParamCodeUInt(\&byId)
{
    WebUser::menu('device');
    my $dev = shift() || return 'notfound';
    my $jmp = shift() || return 'notfound';
    return 'notfound' if $jmp->{devid} != $dev->{id};
    
    $jmp->{data} = _inf($jmp);
    
    return
        'jumpinfo',
        dev => $dev,
        jmp => $jmp,
        inf => $jmp->{data},
        mapcenter => $jmp->{data} ? $jmp->{data}->{center} : undef;
}
        
1;
