/**
 * Form AJAX functions
 * ------------------
 */

function ajaxOK(data) {
    return (typeof(data) === 'object') && (data.ok);
}
function ajaxERR(data) {
    var iserr = (typeof(data) === 'object') && (data.error);
    if (iserr && !data.message && (data.error.length > 0)) {
        data.message = data.error;
    }
    return iserr;
}

// Для быстрых операций на выполнение, без редиректов и возвращаемого кода - только OK/ERROR
function ajaxF(url,data,func) {
    data['ajax'] = 1;
    
    $.ajax({
        url: url,
        type: 'POST',
        dataType: 'json',
        data: data,
        success: function (data) {
            if (ajaxOK(data)) {
                if (func) func(data);
            }
            else
            if (ajaxERR(data)) {
                var mess = data.message ? data.message : 'Неизвестная ошибка';
                console.log('ajaxF return error: ', mess);
                toastr.error(mess);
            }
            else {
                console.log('ajaxF request fail');
                toastr.error('Ошибка в ответе с сервера');
            }
        },
        error: function() {
            toastr.error('Ошибка сервера');
        },
        
    });
}

var htmlStyleUpdate = function($div) {
    
    /**
     * form ajax submit
     */
    
    // when the form is submitted
    var $formall = $div.find("form.ajax-submit");
    $formall.on("submit", function(e) {
        // if the validator does not prevent form submit
        if (!e.isDefaultPrevented()) {
            var $this = $(this);
            var url = $this.attr('action');
            if (!url) {
                // если вообще ничего не получили - значит ошибка
                toastr.error('Ошибка URL формы');
                return false;
            }
            
            $this.find('[name]').each(function() {
                // Удаляем старые ошибки полей
                var $grp = $(this).closest('.form-group');
                $grp.removeClass('has-error');
                $grp.find('span.help-block').remove();
            });
            
            $.ajax({
                url: url,
                type: 'POST',
                dataType: 'json',
                data: $this.serialize() + '&ajax=1',
                success: function (data) {
                    if (ajaxOK(data)) {
                        toastr.success('Выполнено OK');
                        if (data.redirect)
                            setTimeout(function(){
                                    //window.location = data.redirect;
                                    window.location.assign(data.redirect);
                            }, 1000);
                        // Закрываем модальное окно, если такое есть
                        $this.closest('div.modal').modal('hide');
                    }
                    else
                    if (ajaxERR(data)) {
                        var mess = data.message ? data.message : 'Неизвестная ошибка';
                        toastr.error(mess);
                        if (data.field)
                            $.each(data.field, function(fld,err) {
                                console.log(fld, err);
                                var $inp = $this.find('[name='+fld+']');
                                var $grp = $inp.closest('.form-group');
                                $grp.addClass('has-error');
                                var $txt = $grp.find('span.help-block');
                                if ($txt.length == 0)
                                    $inp.after($txt = $('<span class="help-block"></span>'));
                                $txt.html(err);
                            });
                    }
                    else {
                        toastr.error('Ошибка в ответе с сервера');
                    }
                },
                error: function() {
                    toastr.error('Ошибка сервера');
                },
            });
    
            return false;
        }
    });
    
    //Initialize Select2 Elements
    $div.find('.select2').select2();
    
    // Autocomplete
    $div.find('input.autocomplete').autoComplete();
    
    // Input Mask
    $div.find('[data-mask]').inputmask();
    
    // tooltip
    $div.find('[data-toggle="tooltip"]').tooltip();
    
    //iCheck for checkbox and radio inputs
    $div.find('input[type="checkbox"].icheck, input[type="radio"].icheck').iCheck({
        checkboxClass: 'icheckbox_square-blue',
        radioClass   : 'iradio_square-blue',
        increaseArea : '20%' 
    });
    
    /*$div.find('input[type="checkbox"].icheck, input[type="radio"].icheck').each(function(){
        var self = $(this),
            label = self.next(),
            label_text = label.text();
    
        label.remove();
        self.iCheck({
            checkboxClass: 'icheckbox_line-blue',
            radioClass: 'iradio_line-blue',
            insert: '<div class="icheck_line-icon"></div>' + label_text
        });
    });*/
    
    // Action - действие с результатом в виде "ок/ошибка" - м.б. с подтверждением и без
    var xhrOpModal = false;
    function alertByData(data,okmgs) {
        if (ajaxOK(data)) {
            toastr.success(okmgs);
            if (data.redirect)
                setTimeout(function(){
                        //window.location = data.redirect;
                        window.location.assign(data.redirect);
                }, 1000);
        }
        else
        if (ajaxERR(data)) {
            var mess = data.message ? data.message : 'Неизвестная ошибка';
            toastr.error(mess);
        }
        else {
            toastr.error('Ошибка обработки на сервере');
        }
    };
    $div.find('a[data-toggle="action"]').on('click', function() {
        event.preventDefault();
        var $this = $(this);
        //$this.closest('ul.dropdown-menu').dropdown('hide');
        $this.closest('ul.dropdown-menu').parent().removeClass('open');
        var confirm = $this.data('confirm');
        
        if (confirm) {
            // Для подтверждения выводим стандартное модальное окно,
            // а процесс выполнения отображаем в виде крутящихся стрелок на кнопке "выполнить"
            var $modal = $('#opModal');
            if (!$modal.length) return false;
            
            $modal.find('h4.modal-title').text('Подтверждение: ' + $this.text());
            $modal.find('div.modal-body').html(confirm);
            var $btn = $modal.find('button.btn-primary');
            $btn.show();
            $btn.unbind('click');
            $modal.modal('show');
            
            $btn.on('click', function () {
                if (xhrOpModal)
                    xhrOpModal.abort();
                
                if ($btn.find('i').length == 0) {
                    $btn.prepend('<i class="fa fa-refresh fa-spin"></i>');
                    $btn.attr("disabled", true);
                }
                
                var url = $this.prop('href');
                if (url.match(/\?/i) !== null){
                    url = url.replace(/\?/, '?ajax=1&');
                }else{
                    url = url + '?ajax=1';
                }
                
                xhrOpModal = $.ajax({
                    url: url,
                    type: 'GET',
                    dataType: 'json',
                    success: function (data) {
                        if (ajaxOK(data)) {
                            $btn.hide();
                            $btn.unbind('click');
                            $modal.modal('hide');
                        }
                        alertByData(data,$this.text());
                    },
                    error: function() {
                        toastr.error('Ошибка сервера');
                    },
                    complete: function() {
                        xhrOpModal = false;
                        $btn.find('i').remove();
                        $btn.removeAttr("disabled");
                    }
                });
                
                return false;
            });
        }
        else {
            // Без подтверждения - просто делаем запрос и алертом выводим результат
            $.ajax({
                url: $this.prop('href'),
                type: 'POST',
                dataType: 'json',
                data: 'ajax=1',
                success: function(data) { alertByData(data, $this.text()); },
                error: function() {
                    toastr.error('Ошибка сервера');
                },
            });
        }
        
        return false;
    });
    
    
    // resultmodal - действие с результатом, которое надо отобразить в модальном окне - м.б. с подтверждением и без
    function showResultModal(data,title) {
        var $modal = $('#opModal');
        if (!$modal.length) return false;
        $modal.find('h4.modal-title').text('Результат операции: ' + title);
        $modal.find('button.btn-primary').hide().unbind('click');
        $modal.find('div.modal-body').html(data);
        $modal.modal('show');
    };
    $div.find('a[data-toggle="resultmodal"]').on('click', function() {
        event.preventDefault();
        var $this = $(this);
        //$this.closest('ul.dropdown-menu').dropdown('hide');
        $this.closest('ul.dropdown-menu').parent().removeClass('open');
        var confirm = $this.data('confirm');
        
        if (confirm) {
            // Для подтверждения выводим стандартное модальное окно,
            // а процесс выполнения отображаем в виде крутящихся стрелок на кнопке "выполнить"
            var $modal = $('#opModal');
            if (!$modal.length) return false;
            
            $modal.find('h4.modal-title').text('Подтверждение: ' + $this.text());
            $modal.find('div.modal-body').html(confirm);
            var $btn = $modal.find('button.btn-primary');
            $btn.show();
            $btn.unbind('click');
            $modal.modal('show');
            
            $btn.on('click', function () {
                if (xhrOpModal)
                    xhrOpModal.abort();
                
                if ($btn.find('i').length == 0) {
                    $btn.prepend('<i class="fa fa-refresh fa-spin"></i>');
                    $btn.attr("disabled", true);
                }
                
                xhrOpModal = $.ajax({
                    url: $this.prop('href'),
                    dataType: 'html',
                    success: function(data) { showResultModal(data, $this.text()); },
                    error: function() {
                        toastr.error('Ошибка сервера');
                    },
                    complete: function() {
                        xhrOpModal = false;
                        $btn.find('i').remove();
                        $btn.removeAttr("disabled");
                    }
                });
                
                return false;
            });
        }
        else {
            // Без подтверждения - просто делаем запрос и алертом выводим результат
            $.ajax({
                url: $this.prop('href'),
                dataType: 'html',
                success: function(data) { showResultModal(data, $this.text()); },
                error: function() {
                    toastr.error('Ошибка сервера');
                },
            });
        }
        
        return false;
    });
    
    
    // Элемент, который надо открыть в модальном окне по ссылке
    // Например - редактирование поля: в ссылке отображаем значение, а по ссылке открывается форма редактирования
    $div.find('a').filter('.editable,[data-modal-editing]').on('click', function() {
        event.preventDefault();
        var $this = $(this);
        
        var elid = $this.data('modal-editing');
        var $el = elid ? $('#'+elid) : $this.find('.editing');
        if ($el.length < 1)
            return false;
        var $form = $el.filter('form');
        
        var $modal = $('#opModal');
        if (!$modal.length) return false;
        
        $modal.find('h4.modal-title').text($this.data('modal-title') || ($form.length ? 'Редактирование поля' : $this.text()));
        var $el1 = $el.clone();
        $modal.find('div.modal-body').html('').append($el1);
        $el1.show();
        var $btn = $modal.find('button.btn-primary');
        if ($form.length)
            $btn.show();
        else
            $btn.hide();
        $btn.unbind('click');
        $modal.modal('show');
        
        if ($form.length == 0)
            return false;
        
        $btn.on('click', function(e) {
            var url = $form.attr('action');
            if (!url) {
                // если вообще ничего не получили - значит ошибка
                toastr.error('Ошибка URL формы');
                return false;
            }
            
            $.ajax({
                url: url,
                type: 'POST',
                dataType: 'json',
                data: $el1.filter('form').serialize() + '&ajax=1',
                success: function (data) {
                    if (ajaxOK(data)) {
                        $btn.hide();
                        $btn.unbind('click');
                        $modal.modal('hide');
                        toastr.success('Выполнено OK');
                        if (data.redirect)
                            setTimeout(function(){
                                    //window.location = data.redirect;
                                    window.location.assign(data.redirect);
                            }, 1000);
                    }
                    else
                    if (ajaxERR(data)) {
                        var mess = data.message ? data.message : 'Неизвестная ошибка';
                        toastr.error(mess);
                        if (data.field)
                            $.each(data.field, function(fld,err) {
                                console.log(fld, err);
                                var $inp = $this.find('[name='+fld+']');
                                var $grp = $inp.closest('.form-group');
                                $grp.addClass('has-error');
                                var $txt = $grp.find('span.help-block');
                                if ($txt.length == 0)
                                    $inp.after($txt = $('<span class="help-block"></span>'));
                                $txt.html(err);
                            });
                    }
                    else {
                        toastr.error('Ошибка обработки на сервере');
                    }
                }
            });
    
            return false;
        });
        
        return false;
    });
    
    
    // Просто модальные окна и обычные слои по ссылке
    $div.find('[data-modal-show]').on('click', function() {
        event.preventDefault();
        var $this = $(this);
        
        var elid = $this.data('modal-show');
        console.log('elid', elid);
        if (!elid)
            return false;
        $('#'+elid).modal('show');
        
        return true;
    });
    
    
    // Копирование в буфер обмена
    $div.find('[data-clipboard-copy]').on('click', function() {
        var $this = $(this);
        var from = $this.data('clipboard-copy');
        
        var str =
                from == 'title' ?
                    $this.attr('title') || $this.data('original-title') :
                from == 'content' ?
                    $this.text() :
                    from;
        var regex = /<br\s*[\/]?>/gi;
        str = str.replace(regex, "\n");
    
        let tmpin   = document.createElement('TEXTAREA');
        //let focus = document.activeElement;
        tmpin.value = str;
        //console.log('copy8: ', str);
        //document.body.appendChild(tmpin);
        this.appendChild(tmpin);
        tmpin.select();
        document.execCommand('copy');
        //document.body.removeChild(tmpin);
        this.removeChild(tmpin);
        //focus.focus();
        toastr.success('Скопировано в буфер обмена');
        return false;
    });
    
    // Редактируемые элементы формы
    $div.find('.form-adv').find('.btn-collapse').on('click', function() {
        $(this).closest('dd').find('.form-collapsed').slideToggle();
        return false;
    });
    //$div.find('.form-adv').find('.btn-collapse').closest('dd').on('click', function() {
    //    $(this).find('.form-collapsed').slideToggle();
    //});
    
    // slimScroll
    $div.find('[data-slimscroll]').each(function() {
        var $this = $(this);
        var h = $this.attr('data-slimscroll') || '250px';
        $this.slimScroll({ height: h });
    });
};

$(function () {
    'use strict'
    
    htmlStyleUpdate($(document));
})
