package CUser::_root;

use Clib::strict8;

sub _root :
        Simple
{
    WebUser::menu('serv');
    
    return
        'servlist';
}
        
1;
