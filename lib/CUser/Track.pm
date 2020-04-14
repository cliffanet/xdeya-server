package CUser::Track;

use Clib::strict8;

sub byId {
    sqlGet(track => shift());
}

sub _root :
        ParamCodeUInt(\&CUser::Device::byIdMy)
        ParamCodeUInt(\&byId)
{
    WebUser::menu('device');
    my $dev = shift() || return 'notfound';
    my $trk = shift() || return 'notfound';
    return 'notfound' if $trk->{devid} != $dev->{id};
    
    $trk->{data} = json2data($trk->{data});
    
    my $interval = 0;
    if (@{ $trk->{data}||[] }) {
        $interval =
            $trk->{data}->[@{ $trk->{data}||[] }-1]->{mill} -
            $trk->{data}->[0]->{mill};
    }
    
    
    return
        'trackinfo',
        dev => $dev,
        trk => $trk,
        interval => $interval;
}
        
1;
