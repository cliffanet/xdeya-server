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
    my @track = (); # список треков, элемент: { name => '', seg => [[], []...] }
    my $track;
    my $seg;
    my $state = '---';
    
    my @flags = qw/vgps vloc vvert vspeed vhead vtime fl fl fl fl fl jmpbeg jmpdeciss bup bsel bdn/;
    foreach my $p (@{ $trk->{data}||[] }) {
        # debug для flags
        my $f = 1;
        $p->{flagcode} = [];
        foreach my $flag (@flags) {
            push(@{ $p->{flagcode} }, $flag) if $p->{flags} & $f;
            $f = $f << 1;
        }
        
        # треки разделяем при изменении состояния state
        if (($state ne $p->{state}) ||
                ((@$seg >= 2) && ($seg->[@$seg-1]->{tmoffset} - $seg->[0]->{tmoffset} >= 60000)) # отладочное разделение ни куски по 1 мин
            ) {
            push @point, $p; # точки перехода между состояниями
            
            $seg = [];
            $track = { name => $p->{state}, pnt => $p, pntcount => 0, seg => [$seg] };
            push @track, $track;
            
            $state = $p->{state};
        }
        elsif ($p->{flags} & 0x0001) { # gpsok ?
            push @$seg, $p;
            $track->{pntcount} ++;
        }
        elsif (@$seg) {
            $seg = [];
            push @{ $track->{seg} }, $seg;
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
        tracklist => \@track,
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
    
    my @flags = qw/vgps vloc vvert vspeed vhead vtime fl fl fl fl fl jmpbeg jmpdeciss bup bsel bdn/;
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
