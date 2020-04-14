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
        $millbeg = $trk->{data}->[0]->{mill};
        $interval = $trk->{data}->[@{ $trk->{data}||[] }-1]->{mill} - $interval;
        $trk->{data}->[@{ $trk->{data}||[] }-1]->{islast} = 1;
    }
    
    foreach my $e (@{ $trk->{data}||[] }) {
        $e->{sec} = ($e->{mill} - $millbeg) / 1000;
    }
    
    # Агрегируем данные по 1, 5 и 10 сек, чтобы проще выводить на графике
    my @prep = ();
    my @f = qw/alt vspeed hspeed/; # Поля, у которых вычисляем средние значения
    foreach my $t (1, 5, 10) {
        my @full = (); # Полный итоговый список агрегированных значений
        my @sub = (); # Список внутри агрегации
        my $next = $t; 
        foreach my $e (@{ $trk->{data}||[] }) {
            while (($e->{sec} >= $next) || $e->{islast}) {
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
                last if $e->{islast};
            }
            
            push @sub, $e;
        }
        push @prep, 'bysec'.$t => \@full;
    }
    
    
    return
        'trackinfo',
        dev => $dev,
        trk => $trk,
        millbeg => $millbeg,
        interval => $interval,
        @prep;
}
        
1;
