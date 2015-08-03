Ensembl.Panel.SearchBox = Ensembl.Panel.extend({
  init: function() {
    this.base();
    // Extend jQuery UI autocomplete widget to add "catgories"
    $.widget("custom.catAutocomplete", $.ui.autocomplete, {
      _renderMenu: function(ul, items) {
        var that = this; 
        var currentCategory = "";
        $.each(items, function(index, item) {
          if (item.category != currentCategory) {
            $("<li></li>").addClass("ui-menu-category").data("ui-autocomplete-category", item).append(item.category).appendTo(ul);
            currentCategory = item.category;
          }
          that._renderItemData(ul, item);
        });
     },
     _renderItem: function(ul, item) {
       var regex = new RegExp("(?![^&;]+;)(?!<[^<>]*)(" + $.ui.autocomplete.escapeRegex(this.term) + ")(?![^<>]*>)(?![^&;]+;)", "gi");
       item.label = item.label.replace(regex, "<strong>$1</strong>");
       return $("<li></li>").data("ui-autocomplete-item", item).append("<a>" + item.label + "</a>").appendTo(ul);
     }
    });
    $("#se_q").catAutocomplete({
      source: function(request, response) {
        $.ajax({
          url: "/Multi/Ajax/search_autocomplete",
          dataType: "json",
          data: {
            term: request.term,
            format: "json"
          },
          success: function(data) {
              response($.map(data, function(item) {
                if (typeof item === 'string') {
                  return {
                    label: item,
                    value: item,
                    category: 'Suggested Term'
                  }
                } else {
                  return {
                    label: item.value,
                    value: item.value,
                    url: item.url,
                    category: 'Species'
                  }
                }
              }));
          }
        });
      },
      minLength: 3,
      select: function(event, ui) {
        $("#se_q").val(ui.item.value);
        if(typeof ui.item.url !== 'undefined') {
          window.location.href = ui.item.url;
        } else {
          $("#searchForm").submit();
        }
      }
    });
  }
});
