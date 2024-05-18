class SortableTable {
    constructor(options) {
        if (typeof(options.sortable) === 'undefined')
            options.sortable = true;
        this.element = options.element;
        this.headers = options.headers;
        this.rows = options.rows;
        this.row_classes = options.row_classes;
        this.clickable_row_callback = options.clickable_row_callback;
        this.filter_callback = options.filter_callback;
        this.options = options;
        let table_div = $(`<div class="table-responsive" style="max-width: 100%; overflow-x: auto;">`);
        let table = $("<table class='table table-sm table-condensed narrow' style='display: none;'>");
        table.css('user-select', 'none');
        if (options.xs)
            table.addClass('xs');
        table_div.append(table);
        let thead = $('<thead>');
        table.append(thead);
        let self = this;
        for (let i = 0; i < options.headers.length; i++) {
            let cell = options.headers[i];
            if (options.sortable) {
                cell.addClass('hover:bg-stone-200');
                cell.data('index', i);
                cell.data('sort_direction', null);
                cell.css('cursor', 'pointer');
                cell.click(function (e) {
                    let index = $(e.target).closest('th').data('index')
                    let direction = $(e.target).closest('th').data('sort_direction') || 'desc';
                    direction = (direction === 'desc') ? 'asc' : 'desc';
                    $(e.target).closest('th').data('sort_direction', direction);
                    self.sort_rows(index, direction === 'desc');
                });
            }
            thead.append(cell);
        }
        let tbody = $('<tbody>');
        this.tbody = tbody;
        table.append(tbody);
        let row_classes = options.row_classes ?? [];
        for (let i = 0; i < options.rows.length; i++) {
            let row = options.rows[i];
            this.add_row(row, false, false, row_classes[i] ?? []);
        }
        this.element.append(table_div);
        table.css('display', 'table');
    }

    add_row(row, highlight, prepend, row_classes) {
        if (typeof(row_classes) === 'undefined' )
            row_classes = [];
        if (typeof(prepend) === 'undefined')
            prepend = false;
        if (row === null) return;
        if (typeof(highlight) === 'undefined')
            highlight = true;
        let tr = $('<tr>');
        for (let c of row_classes)
            tr.addClass(c);
        let self = this;
        if (this.options.clickable_rows) {
            tr.addClass('clickable_row');
            tr.click(function (e) {
                self.clickable_row_callback($(e.target).closest('tr').data('row_data'));
            });
        }
        tr.data('row_data', row[0])
        tr.append(row.slice(1));
        let i = 0;
        let j = 0;
        let col_index = {};
        for (let cell of tr.find('td')) {
            let colspan = parseInt($(cell).attr('colspan') || 1);
            for (let k = 0; k < colspan; k++)
                col_index[j + k] = i;
            j += colspan;
            i += 1;
        }
        tr.data('col_index', col_index);
        if (prepend)
            this.tbody.prepend(tr);
        else
            this.tbody.append(tr);
        if (highlight) {
            tr.addClass('hl').addClass('has_hl');
            setTimeout(function() {
                tr.removeClass('hl');
            }, 2000);
        }
    }

    highlight_row(tr) {
        tr.addClass('hl').addClass('has_hl');
        setTimeout(function() {
            tr.removeClass('hl');
        }, 2000);
    }

    update_filter() {
        if (!this.filter_callback)
            return;
        for (let tr of this.tbody.find('tr')) {
            if (this.filter_callback($(tr).data('row_data')))
                $(tr).show();
            else
                $(tr).hide();
        }
    }

    sort_rows(index, descending) {
        let th = $(this.headers[index]);
        let type = $(th).data('type') || 'string';
        let rows = this.tbody.find('tr').get();
        rows.sort(function (_a, _b) {
            let result = 0;
            let aci = $(_a).data('col_index');
            let bci = $(_b).data('col_index');
            let a = $($(_a).find('td').eq(aci[index]));
            let b = $($(_b).find('td').eq(bci[index]));
            if (type === 'int') {
                let ai = $(a).data('sort_value');
                if (ai === null) ai = parseInt($(a).text());
                let bi = $(b).data('sort_value');
                if (bi === null) bi = parseInt($(b).text());
                if (isNaN(ai) && !isNaN(bi))
                    result = 1;
                else if (!isNaN(ai) && isNaN(bi))
                    result = -1;
                else if (isNaN(ai) && isNaN(bi))
                    result = 0;
                else
                    result = ai - bi;
            } else if (type === 'string') {
                let as = $(a).data('sort_value') || $(a).text();
                let bs = $(b).data('sort_value') || $(b).text();
                result = as.localeCompare(bs);
            }
            if (descending) result = -result;
            return result;
        });
        for (let row of rows)
            this.tbody.append(row);
        // for (let row of this.rows) {
        //     let tr = $('<tr>');
        //     tr.append(row);
        //     this.tbody.append(tr);
        // }
    }
}

