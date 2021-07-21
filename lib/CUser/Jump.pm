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

sub pntCenter {
    my $mapcenter;
    my @gpsfail = ();
    foreach my $pgrp (@_) {
        my $tofail = 
            ($pgrp->{code} ne 'gpsfail');
        foreach my $p (@{ $pgrp->{list} }) {
            $p->{gpsok} = $p->{flags} & 0x0001 ? 1 : 0;
            if ($p->{gpsok}) {
                $mapcenter ||= $p
            }
            elsif ($tofail) {
                push @gpsfail, {
                    %$p,
                    grpname => $pgrp->{name}, 
                    grpcode => $pgrp->{code},
                    grpcol  => $pgrp->{col},
                };
            }
        }
        if ($tofail) {
            @{ $pgrp->{list} } =
                grep { $_->{gpsok} }
                @{ $pgrp->{list} };
        }
    }
    
    return ($mapcenter, @gpsfail);
}
sub pntJump {
    my @pnt = ();
    foreach my $pname (@{ c(point => 'jump')||[] }) {
        my $pnt = shift() || next;
        push @pnt, $pnt = { %$pnt };
        $pnt->{name} = sprintf $pname, $pnt->{alt};
    }
    return {
        list    => [@pnt],
        code    => 'jump',
        col     => 'blue',
        name    => c(point => group => 'jump'),
    };
}

sub _root :
        ParamCodeUInt(\&CUser::Device::byIdMy)
        ParamCodeUInt(\&byId)
{
    WebUser::menu('device');
    my $dev = shift() || return 'notfound';
    my $jmp = shift() || return 'notfound';
    return 'notfound' if $jmp->{devid} != $dev->{id};
    
    my ($prev) = sqlSrch(jump => devid => $dev->{id}, sqlLt(id => $jmp->{id}), sqlLimit(1), sqlOrder('-id'));
    my ($next) = sqlSrch(jump => devid => $dev->{id}, sqlGt(id => $jmp->{id}), sqlLimit(1), sqlOrder('id'));
    
    my $inf = ($jmp->{data} = _inf($jmp));
    
    # точки на карте
    my @pnt = CUser::Jump::pntJump($inf->{beg}, $inf->{cnp}, $inf->{end});
    my ($mapcenter, @gpsfail) = CUser::Jump::pntCenter(@pnt);
    
    return
        'jumpinfo',
        dev         => $dev,
        jmp         => $jmp,
        prev        => $prev,
        next        => $next,
        inf         => $jmp->{data},
        mapcenter   => $mapcenter,
        point       => [ @pnt ],
        gpsfail     => [ @gpsfail ];
}
        
1;
