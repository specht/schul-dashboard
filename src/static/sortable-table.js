class SortableTable {
    constructor(options) {
        this.element = options.element;
        this.headers = options.headers;
        this.rows = options.rows;
        this.clickable_row_callback = options.clickable_row_callback;
        this.filter_callback = options.filter_callback;
        let table_div = $(`<div class="table-responsive" style="max-width: 100%; overflow-x: auto;">`);
        let table = $("<table class='table table-sm table-condensed narrow'>");
        table_div.append(table);
        let thead = $('<thead>');
        table.append(thead);
        let self = this;
        for (let i = 0; i < options.headers.length; i++) {
            let cell = options.headers[i];
            cell.data('index', i);
            let bu_sort_asc = $(`<span class='cursor-pointer inline-block bg-slate-900 hover:text-black rounded-full text-slate-500 font-sm ml-2 w-6 h-6 text-center'><i class='fa fa-angle-down'></i></span>`);
            bu_sort_asc.click(function(e) { self.sort_rows($(e.target).closest('th').data('index'), false); });
            cell.append(bu_sort_asc);
            let bu_sort_desc = $(`<span class='cursor-pointer inline-block bg-slate-900 hover:text-black rounded-full text-slate-500 font-sm ml-1 w-6 h-6 text-center'><i class='fa fa-angle-up'></i></span>`);
            bu_sort_desc.click(function(e) { self.sort_rows($(e.target).closest('th').data('index'), true); });
            cell.append(bu_sort_desc);
            thead.append(cell);
        }
        let tbody = $('<tbody>');
        table.append(tbody);
        for (let row of options.rows) {
            let tr = $('<tr>');
            if (options.clickable_rows) {
                tr.addClass('clickable_row');
                tr.click(function(e) {
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
            tbody.append(tr);
        }
        this.element.append(table_div);
        this.tbody = tbody;
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
        rows.sort(function(_a, _b) {
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
