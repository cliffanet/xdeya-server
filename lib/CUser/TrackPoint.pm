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
    my $user = user() || return;
    
    my @grp = sqlSrch(pointgroup => uid => $user->{id}, sqlOrder('name'));
    @grp || return;
    my %grp = map { ($_->{id} => $_) } @grp;
    my @p =
        map {
            $_->{grp} = $grp{$_->{grpid}};
            $_;
        }
        sqlSrch(pointlist => uid => $user->{id}, sqlOrder('alt', 'name'));
    
    my @pnt = ();
    my @l = ();
    my @g = ();
    my $pname = c(point => 'custom');
    foreach my $p (@_) {
        my ($pu) = (
            (grep { $_->{alt} >= $p->{alt} } @l),
            (grep { $_->{alt} <= $p->{alt} } @g),
        );
        @l = grep { $_->{alt} < $p->{alt} } @p;
        @g = grep { $_->{alt} > $p->{alt} } @p;
        
        $pu || next;
        
        my $pnt = { %$p };
        $pnt->{name} = sprintf $pname, $pu->{grp}->{name}, $pu->{name}, $pnt->{alt};
        $pnt->{grpid} = $pu->{grpid};
        push @pnt, $pnt;
    }
    return 
        map {
            my $grpid = $_->{id};
            {
                list    => [ grep { $_->{grpid} == $grpid; } @pnt ],
                code    => 'custom'.$_->{id},
                name    => $_->{name},
                col     => 'orange',
                bscol   => 'warning',
                visible => 1,
            }
        }
        @grp;
}

sub _root :
        Simple
{
    my $user = user() || return;
    
    my @grp = sqlSrch(pointgroup => uid => $user->{id}, sqlOrder('name'));
    my %grp = 
        map { $_->{list} = []; ($_->{id} => $_) }
        @grp;
    
    my @pnt = sqlSrch(pointlist => uid => $user->{id}, sqlOrder('alt', 'name'));
    foreach my $pnt (@pnt) {
        my $grp = $grp{ $pnt->{grpid} } || next;
        push @{ $grp->{list} }, $pnt;
    }
    
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
    
    return ok => c(state => trackpoint => 'grpdelok'), redirect => '';
}

sub add :
        Title('Добавление пользовательской точки')
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
    
    # группа
    my $grpid = $p->uint('grpid');
    if (!$grpid) {
        push @ferr, grpid => 'empty';
    }
    elsif (!sqlSrch(pointgroup => id => $grpid, uid => $user->{id})) {
        push @ferr, grpid => 'notfound';
    }
    
    # высота
    my $alt = $p->uint('alt');
    if (!$p->exists('alt') || ($p->str('alt') eq '')) {
        push @ferr, alt => 'empty';
    }
    elsif ($p->raw('alt') !~ /^\d+$/) {
        push @ferr, alt => 'format';
    }
    
    # ошибки ввода данных
    if (@ferr) {
        return err => 'input', field => { @ferr };
    }
    
    # Добавляем в базу
    my $pntid = sqlAdd(
        pointlist =>
        uid     => $user->{id},
        dtadd   => Clib::DT::now(),
        name    => $name,
        grpid   => $grpid,
        alt     => $alt
    ) || return err => 'db';
    
    return ok => c(state => trackpoint => 'addok'), redirect => '';
}

sub set :
        ParamCodeUInt(\&byIdPnt)
        Title('Изменение пользовательской точки')
        ReturnOperation
{
    my $pnt = shift() || return err => 'notfound';
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
        if ($name ne $pnt->{name}) {
            push @upd, name => $name;
        }
    }
    
    # группа
    if ($p->exists('grpid')) {
        my $grpid = $p->uint('grpid');
        if (!$grpid) {
            push @ferr, grpid => 'empty';
        }
        elsif (!sqlSrch(pointgroup => id => $grpid, uid => $pnt->{uid})) {
            push @ferr, grpid => 'notfound';
        }
        if ($grpid != $pnt->{grpid}) {
            push @upd, grpid => $grpid;
        }
    }
    
    # высота
    if ($p->exists('alt')) {
        my $alt = $p->uint('alt');
        if ($p->str('alt') eq '') {
            push @ferr, alt => 'empty';
        }
        elsif ($p->raw('alt') !~ /^\d+$/) {
            push @ferr, alt => 'format';
        }
        if ($alt != $pnt->{alt}) {
            push @upd, alt => $alt;
        }
    }
    
    # ошибки ввода данных
    if (@ferr) {
        return err => 'input', field => { @ferr };
    }
    
    # Осталось ли, что сохранять
    @upd || return error => 'nochange';
    
    # В базе
    my $pntid = sqlUpd(
        pointlist => $pnt->{id},
        @upd,
    ) || return err => 'db';
    
    return ok => c(state => trackpoint => 'setok'), redirect => '';
}

sub del :
        ParamCodeUInt(\&byIdPnt)
        Title('Удаление пользовательской точки')
        ReturnOperation
{
    my $pnt = shift() || return err => 'notfound';
    my $user = user() || return;
    
    # В базе
    sqlDel(pointlist => $pnt->{id})
        || return err => 'db';
    
    return ok => c(state => trackpoint => 'delok'), redirect => '';
}

        
1;
