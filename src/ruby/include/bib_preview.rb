# Neues Design (Vorschau) for the library pages (bibliothek.html, bib_*.html):
# both library templates (_bib_public_template.html, _bib_template.html) call
# bib_preview_head, which only in the preview loads the area's script and
# says which page and which roles it is for. The pages keep their own markup
# and scripts; preview/bib.js draws them in the new design (book rows,
# tables, the scanner area, the library's own navigation) and
# preview/bib.css styles them. With the preview off it returns '' – the
# pages' bytes stay exactly as before.
class Main < Sinatra::Base
    # the library's pages in the order of its navigation
    BIB_PREVIEW_PAGES = %w(bibliothek bib_browse bib_orders bib_overview bib_books bib_users bib_all_orders
                           bib_scan bib_return bib_discard bib_book bib_book_edit bib_exemplar bib_user bib_confirm
                           bib_process_order bib_add_exemplare bib_print_label bib_shelves bib_scan_shelf
                           bib_scan_isbn bib_postpone bib bib_login)

    def bib_preview_head
        return '' unless ui_preview?
        page = ((request.path rescue '') || '').split('/')[1].to_s
        page = '' unless BIB_PREVIEW_PAGES.include?(page)
        info = {
            :page => page,
            :teacher => teacher_logged_in?,
            :manage => can_manage_bib_logged_in?,
            :special => can_manage_bib_special_access_logged_in?,
            :device => @session_device.to_s,
        }
        "<script>document.body.classList.add('pv-bib'#{page.empty? ? '' : ", 'pv-bib-#{page.tr('_', '-')}'"}); window.PV_BIB = #{info.to_json};</script>" +
        "<script defer src='#{preview_asset('/preview/bib.js')}'></script>"
    end
end
