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
    
    my ($prev) = sqlSrch(track => devid => $dev->{id}, sqlLt(id => $trk->{id}), sqlLimit(1), sqlOrder('-id'));
    my ($next) = sqlSrch(track => devid => $dev->{id}, sqlGt(id => $trk->{id}), sqlLimit(1), sqlOrder('id'));
    
    $trk->{data} = json2data($trk->{data});
    
    my $interval = 0;
    my $millbeg = 0;
    if (@{ $trk->{data}||[] }) {
        $interval = $trk->{data}->[@{ $trk->{data}||[] }-1]->{tmoffset};
        $trk->{data}->[@{ $trk->{data}||[] }-1]->{islast} = 1;
    }

    my $inf = {};
    my $i = 0;
    foreach my $p (@{ $trk->{data}||[] }) {
        $p->{gpsok} = $p->{flags} & 0x0001 ? 1 : 0;
        if (!$inf->{beg}) {
            if ($p->{flags} & 0x0200) { # LI_FLAG_JMPBEG
                $inf->{beg} = $p;
            }
            elsif ($p->{flags} & 0x1000) { # LI_FLAG_JMPDECISS
                my $c = $p->{state} eq 'f' ? 50 : 80;
                $inf->{beg} = $trk->{data}->[$i >= $c ? $i-$c : 0];
            }
        }
        if (!$inf->{cnp}) {
            if ($p->{flags} & 0x0400) { # LI_FLAG_JMPCNP
                $inf->{cnp} = $trk->{data}->[$i >= 60 ? $i-60 : 0];
            }
        }
        if (!$inf->{end}) {
            if ($p->{flags} & 0x0800) { # LI_FLAG_JMPEND
                $inf->{end} = $p;
            }
        }
        $i++;
    }
    
    # Агрегируем данные чтобы графики рисовались более красивыми
    my $tmaggr = $interval / 30;
    my @aggr = ();
    my @acc = ();
    my @f = qw/alt altspeed hspeed/; # Поля, у которых вычисляем средние значения
    foreach my $e (@{ $trk->{data}||[] }) {
        if ((my $cnt = @acc) && ($e->{tmoffset} - $acc[0]->{tmoffset} > $tmaggr)) {
            my $v = { %{ $acc[0] }, map { ($_ => 0) } @f };
            foreach my $s (@acc) {
                $v->{$_} += $s->{$_} foreach @f;
            }
            $v->{$_} = $v->{$_}/$cnt foreach @f;
            push @aggr, $v;
            @acc = ();
        }
        push @acc, $e;
    }
    
    my @pnt = CUser::Jump::pntJump($inf->{beg}, $inf->{cnp}, $inf->{end});
    my $mapcenter = CUser::Jump::pntCenter(@pnt);
    
    return
        'trackinfo',
        dev         => $dev,
        trk         => $trk,
        prev        => $prev,
        next        => $next,
        interval    => $interval,
        aggr        => \@aggr,
        mapcenter   => $mapcenter,
        point       => [ @pnt ];
}


sub gpx :
        AllowNoAuth
        ParamUInt
        ParamCodeUInt(\&CUser::Device::byId)
        ParamCodeUInt(\&byId)
        ReturnTxtFile
{
    my $uid = shift() || return 'notfound';
    my $dev = shift() || return 'notfound';
    my $trk = shift() || return 'notfound';
    return 'notfound' if ($uid != $dev->{uid}) || ($trk->{devid} != $dev->{id});
    
    $trk->{data} = json2data($trk->{data});
    
    my $interval = 0;
    if (@{ $trk->{data}||[] }) {
        my $last = $trk->{data}->[@{ $trk->{data}||[] }-1];
        $interval = $last->{tmoffset};
        $last->{islast} = 1;
    }
    
    my @point = ();
    my @seg = ();
    my $seg;
    my $state = '---';
    
    my @flags = qw/vgps vloc vvert vspeed vhead vtime fl fl fl jmpbeg jmpcnp jmpend jmpdeciss bup bsel bdn/;
    foreach my $p (@{ $trk->{data}||[] }) {
        # debug для flags
        my $f = 1;
        $p->{flagcode} = [];
        foreach my $flag (@flags) {
            push(@{ $p->{flagcode} }, $flag) if $p->{flags} & $f;
            $f = $f << 1;
        }
        $p->{gpsok} = $p->{flags} & 0x0001 ? 1 : 0;
        
        if (($state ne $p->{state}) && $p->{gpsok}) {
            push @point, { %$p, bystate => 1 };
            $state = $p->{state};
        }
        if ($p->{gpsok}) { # gpsok ?
            if (!$seg) {
                $seg = [];
                push @seg, $seg;
                push @point, { %$p, byseg => 1 };
            }
            push @$seg, $p;
        }
        elsif ($seg) {
            $seg = undef;
        }
    }
    
    my $date = Clib::DT::datetime($trk->{dtbeg});
    $date =~ s/ /_/g;
    $date =~ s/\:/./g;
    
    return
        'trackgpx',
        'application/gpx+xml' => 'jump.'.$trk->{jmpnum}.'-'.$date.'.gpx',
        dev => $dev,
        trk => $trk,
        seglist => \@seg,
        pointlist => \@point,
        interval => $interval;
}

sub csv :
        ParamUInt
        ParamCodeUInt(\&CUser::Device::byId)
        ParamCodeUInt(\&byId)
        ReturnTxtFile
{
    my $uid = shift() || return 'notfound';
    my $dev = shift() || return 'notfound';
    my $trk = shift() || return 'notfound';
    return 'notfound' if ($uid != $dev->{uid}) || ($trk->{devid} != $dev->{id});
    
    $trk->{data} = json2data($trk->{data});
    
    my @flags = qw/vgps vloc vvert vspeed vhead vtime fl fl fl jmpbeg jmpcnp jmpend jmpdeciss bup bsel bdn/;
    foreach my $p (@{ $trk->{data}||[] }) {
        # debug для flags
        my $f = 1;
        $p->{flagcode} = [];
        foreach my $flag (@flags) {
            push(@{ $p->{flagcode} }, $flag) if $p->{flags} & $f;
            $f = $f << 1;
        }
    }
    
    my $date = Clib::DT::datetime($trk->{dtbeg});
    $date =~ s/ /_/g;
    $date =~ s/\:/./g;
    
    return
        'trackcsv',
        'text/csv' => 'jump.'.$trk->{jmpnum}.'-'.$date.'.csv',
        dev => $dev,
        trk => $trk;
}

        
1;
