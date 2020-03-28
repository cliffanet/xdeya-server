package CUser::Device;

use Clib::strict8;

sub byId {
    sqlGet(device => shift());
}

sub byIdMy {
    my $user = user() || return;
    my $dev = byId(@_) || return;
    return if $dev->{uid} != $user->{id};
    return $dev;
}

sub allMy {
    my $user = user() || return;
    
    return sqlSrch(device => uid => $user->{id}, deleted => 0);
}

sub _root :
        ParamCodeUInt(\&byIdMy)
{
    WebUser::menu('device');
    my $dev = shift() || return 'notfound';
    
    return
        'deviceinfo', dev => $dev;
}

sub list :
        Title('Все устройства')
{
    my $user = user() || return;
    WebUser::menu('device');
    
    my $list = shift() || [ allMy() ];
    
    return
        'devicelist', list => $list;
}

sub add :
        Title('Добавление устройства')
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
    my $devid = sqlAdd(
        device =>
        uid     => $user->{id},
        dtadd   => Clib::DT::now(),
        name    => $name,
    ) || return err => 'db';
    
    return ok => c(state => device => 'addok'), redirect => [device => $devid];
}

sub del :
        Title('Удаление устройства')
        ParamCodeUInt(\&byIdMy)
        ReturnOperation
{
    my $dev = shift() || return err => 'notfound';
    
    sqlDel(device => $dev->{id})
        || return err => 'db';
    
    return ok => c(state => device => 'delok'), redirect => 'device/list';
}
        
1;
