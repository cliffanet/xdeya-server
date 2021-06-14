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
    my $millbeg = 0;
    if (@{ $trk->{data}||[] }) {
        $interval = $trk->{data}->[@{ $trk->{data}||[] }-1]->{tmoffset};
        $trk->{data}->[@{ $trk->{data}||[] }-1]->{islast} = 1;
    }

    my $mapcenter;
    my %inf = ();
    my $i = 0;
    foreach my $p (@{ $trk->{data}||[] }) {
        $p->{gpsok} = $p->{flags} & 0x0001 ? 1 : 0;
        $mapcenter ||= $p if $p->{gpsok};
        if (!$inf{beg}) {
            if ($p->{flags} & 0x0200) { # LI_FLAG_JMPBEG
                $inf{beg} = $p;
            }
            elsif ($p->{flags} & 0x1000) { # LI_FLAG_JMPDECISS
                my $c = $p->{state} eq 'f' ? 50 : 80;
                $inf{beg} = $trk->{data}->[$i >= $c ? $i-$c : 0];
            }
        }
        if (!$inf{cnp}) {
            if ($p->{flags} & 0x0400) { # LI_FLAG_JMPCNP
                $inf{cnp} = $trk->{data}->[$i >= 60 ? $i-60 : 0];
            }
        }
        if (!$inf{end}) {
            if ($p->{flags} & 0x0800) { # LI_FLAG_JMPEND
                $inf{end} = $p;
            }
        }
        $i++;
    }
    
    # Агрегируем данные по 1, 5 и 10 сек, чтобы проще выводить на графике
    my @prep = ();
    my @f = qw/alt altspeed hspeed/; # Поля, у которых вычисляем средние значения
    foreach my $t (1, 3, 5) {#, 10) {
        my @full = (); # Полный итоговый список агрегированных значений
        my @sub = (); # Список внутри агрегации
        my $next = $t;
        foreach my $e (@{ $trk->{data}||[] }) {
            while ((($e->{tmoffset}/1000) >= $next) || $e->{islast}) {
                my $el = { %{ $sub[0]||{ sec => $next-$t } } };
                $el->{$_} = 0 foreach @f;
                if (my $cnt = @sub) { # вычисляем среднее по полям
                    foreach my $s (@sub) {
                        $el->{$_} += $s->{$_} foreach @f;
                    }
                    $el->{$_} = $el->{$_}/$cnt foreach @f;
                }
                push @full, $el;
                @sub = ();
                $next += $t; # Будем последовательно заполнять равномерно интервал, даже если есть пропуски в самом треке
                if ($e->{islast}) {
                    push @full, $e;
                    last;
                }
            }
            
            push @sub, $e;
        }
        push @prep, 'bysec'.$t => \@full;
    }
    
    
    return
        'trackinfo',
        dev => $dev,
        trk => $trk,
        interval => $interval,
        mapcenter => $mapcenter,
        inf => \%inf,
        @prep;
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
