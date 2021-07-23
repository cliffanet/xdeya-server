package CUser::TrackPoint;

use Clib::strict8;

sub byIdGrp {
    my $user = user() || return;
    my $grp = sqlGet(pointgroup => shift()) || return;
    return if $grp->{uid} != $user->{id};
    return $grp;
}
sub byIdPnt {
    my $user = user() || return;
    my $pnt = sqlGet(pointlist => shift()) || return;
    return if $pnt->{uid} != $user->{id};
    return $pnt;
}

sub pntCustom {
    @_ || return;
    
    my @pnt = ();
    my $state = $_[0]->{gpsok};
    my $pname = c(point => 'gps');
    foreach my $p (@_) {
        next if $state == $p->{gpsok};
        my $pnt = { %$p };
        $pnt->{name} = sprintf $pname->{ $p->{gpsok} ? 'ok' : 'fail' }, $pnt->{alt};
        push @pnt, $pnt;
        $state = $p->{gpsok};
    }
    return {
        list    => [@pnt],
        code    => 'custom',
        name    => c(point => group => 'gpsfail'),
        col     => 'red',
        bscol   => 'danger',
        visible => 0,
    };
}

sub _root :
        Simple
{
    my $user = user() || return;
    my @grp = sqlSrch(pointgroup => uid => $user->{id}, sqlOrder('name'));
    
    return
        'trackpoint',
        list    => [ @grp ];
}

sub grpadd :
        Title('Добавление группы точек')
        ReturnOperation
{
    my $user = user() || return;
    my $p = wparam();
    
    # Проверяем поля
    my @ferr = ();
    
    # имя
    my $name = $p->str('name');
    if ($name eq '') {
        push @ferr, name => 'empty';
    }
    
    # ошибки ввода данных
    if (@ferr) {
        return err => 'input', field => { @ferr };
    }
    
    # Добавляем в базу
    my $grpid = sqlAdd(
        pointgroup =>
        uid     => $user->{id},
        dtadd   => Clib::DT::now(),
        name    => $name,
    ) || return err => 'db';
    
    return ok => c(state => trackpoint => 'grpaddok'), redirect => '';
}

sub grpset :
        ParamCodeUInt(\&byIdGrp)
        Title('Изменение группы точек')
        ReturnOperation
{
    my $grp = shift() || return err => 'notfound';
    my $p = wparam();
    
    # Проверяем поля
    my @ferr = ();
    my @upd = ();
    
    # имя
    if ($p->exists('name')) {
        my $name = $p->str('name');
        if ($name eq '') {
            push @ferr, name => 'empty';
        }
        if ($name ne $grp->{name}) {
            push @upd, name => $name;
        }
    }
    
    # ошибки ввода данных
    if (@ferr) {
        return err => 'input', field => { @ferr };
    }
    
    # Осталось ли, что сохранять
    @upd || return error => 'nochange';
    
    # В базе
    my $grpid = sqlUpd(
        pointgroup => $grp->{id},
        @upd,
    ) || return err => 'db';
    
    return ok => c(state => trackpoint => 'grpsetok'), redirect => '';
}

sub grpdel :
        ParamCodeUInt(\&byIdGrp)
        Title('Удаление группы точек')
        ReturnOperation
{
    my $grp = shift() || return err => 'notfound';
    my $user = user() || return;
    
    # Удаляем точки
    sqlDel(pointlist => grpid => $grp->{id})
        || return err => 'db';
    
    # В базе
    sqlDel(pointgroup => $grp->{id})
        || return err => 'db';
    
    return ok => c(state => trackpoint => 'grpsetok'), redirect => '';
}

        
1;
