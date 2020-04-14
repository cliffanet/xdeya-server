package CUser::Jump;

use Clib::strict8;

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
    
    $jmp->{data} = json2data($jmp->{data});
    
    return
        'jumpinfo',
        dev => $dev,
        jmp => $jmp;
}
        
1;
