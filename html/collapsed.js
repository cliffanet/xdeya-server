/**
 * Collapsed AJAX box
 * ------------------
 */

$(function () {
    'use strict';
    
    $('[data-collapsed]').each(function() {
        var $this = $(this);
        
        if (!$this.hasClass('box')) $this.addClass('box');
        if (!$this.hasClass('box-widget')) $this.addClass('box-widget');
        if (!$this.hasClass('collapsed-box')) $this.addClass('collapsed-box');
        
        var title = $this.data('collapsed');
        
        $this.html(
            '<div class="box-header with-border">' +
                '<a href="#" data-widget="collapse">' + title + '</a>' +
                '<div class="box-tools">' +
                    '<button type="button" class="btn btn-box-tool" style="display:none"><i class="fa fa-refresh"></i></button>' +
                    '<button type="button" class="btn btn-box-tool" data-widget="collapse"><i class="fa fa-plus"></i> </button>' +
                '</div> <!-- /.box-tools -->' +
            '</div> <!-- /.box-header -->' +
            '<div class="box-body" style="display: none;">' +
            'Загрузка...' +
            '</div> <!-- /.box-body -->'
        );
        
        $this.boxWidget({
            animationSpeed: 500,
            collapseTrigger: '[data-widget="collapse"]',
            collapseIcon: 'fa-minus',
            expandIcon: 'fa-plus'
        });
        
        var reload = function() {
            var url = $this.data('reload');
            if (!url) return;
            
            if ($this.find('div.overlay').length < 1) {
                $this.append(
                    '<div class="overlay">' +
                      '<i class="fa fa-refresh fa-spin"></i>' +
                    '</div>'
                );
            }
            $this.find('i.fa-refresh').closest('button').show();
            
            
            $.ajax({
                url: url,
                success: function (data) {
                    var $body = $this.find('div.box-body');
                    $body.html(data);
                    if (htmlStyleUpdate) htmlStyleUpdate($body);
                },
                error: function() {
                    $this.find('div.box-body').html('Ошибка получения данных');
                },
                complete: function() {
                    $this.find('div.overlay').remove();
                }
            });
        };
        
        $this.on('expanding.boxwidget', reload);
        $this.find('i.fa-refresh').closest('button').on('click', reload);
        
        $this.on('collapsing.boxwidget', function() {
        //    $this.find('div.box-body').html('Загрузка...');
            $this.find('i.fa-refresh').closest('button').hide();
        });
    });
})
