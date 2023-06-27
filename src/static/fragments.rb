require 'prawn'
require 'prawn/measurement_extensions'
require 'prawn-styled-text'

class Prawn::Document
    def elide_string(s, width, style = {}, suffix = '…')
        return '' if width <= 0
        return s if width_of(s, style) <= width
        suffix_width = width_of(suffix, style)
        width -= suffix_width
        length = s.size
        i = 0
        l = s.size
        r = l
        while width_of(s[0, l], style) > width
            r = l
            l /= 2
        end
        i = 0
        while l < r - 1 do
            m = (l + r) / 2
            if width_of(s[0, m], style) > width
                r = m
            else
                l = m
            end
            i += 1
            break if (i > 1000)
        end
        s[0, l].strip + suffix
    end
end

class BoxPrinter
    def initialize(pdf, left, top, width, height)
        @pdf = pdf
        @left = left
        @top = top
        @width = width
        @height = height
    end

    def print(x, y, s, **opts)
        opts[:width] ||= 1
        opts[:height] ||= 1
        opts[:size] ||= 11
        opts[:rotate] ||= 0
        opts[:align] ||= :center
        left = @left + x * @width
        top = @top - y * @height
        width = @width * opts[:width]
        height = @height * opts[:height]
        at = [left, top]
        s = '' if s == '×'
        s = "#{s}".gsub('-', '–').strip
        unless s.empty?
            @pdf.text_box s, :at => at, :width => width, :height => height, :align => opts[:align], :valign => :center, :size => opts[:size], :inline_format => true, :rotate => opts[:rotate], :overflow => :shrink_to_fit
        end
    end
end

class Main
    def get_zeugniskonferenz_sheets_pdf(cache)
        klassen_for_shorthands = {}
        consider_sus_for_klasse = {}

        ZEUGNIS_KLASSEN_ORDER.each do |klasse|
            consider_sus_for_klasse[klasse] = Set.new()
            liste = @@zeugnisliste_for_klasse[klasse]
            # faecher, lehrer_for_fach, schueler, index_for_schueler, FAECHER_SPRACHEN
            liste[:lehrer_for_fach].each_pair do |fach, shorthands|
                shorthands.each do |shorthand|
                    klassen_for_shorthands[shorthand] ||= Set.new()
                    klassen_for_shorthands[shorthand] << klasse
                end
            end
            klassen_for_shorthands['Lü'] ||= Set.new()
            klassen_for_shorthands['Lü'] << klasse
            liste[:schueler].each do |schueler|
                # STDERR.puts schueler.to_yaml
                email = schueler[:email]
                first_name = schueler[:official_first_name]
                last_name = schueler[:last_name]
                liste[:faecher].each do |fach|
                    sub_faecher = [fach]
                    if FAECHER_SPRACHEN.include?(fach)
                        sub_faecher << "#{fach}_AT"
                        sub_faecher << "#{fach}_SL"
                    end
                    sub_faecher.each do |sub_fach|
                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{sub_fach}/Email:#{email}"]
                        if NOTEN_MARK.include?(note)
                            consider_sus_for_klasse[klasse] << email
                        end
                    end
                end
                zk_marked = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/ZK:marked/Email:#{email}"]
                if zk_marked
                    consider_sus_for_klasse[klasse] << email
                end
            end
            consider_sus_for_klasse[klasse] = consider_sus_for_klasse[klasse].to_a.sort do |a, b|
                @@zeugnisliste_for_klasse[klasse][:index_for_schueler][a] <=> @@zeugnisliste_for_klasse[klasse][:index_for_schueler][b]
            end
        end

        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :landscape, :margin => 0) do
            font_families.update("RobotoCondensed" => {
                :normal => "/app/fonts/RobotoCondensed-Regular.ttf",
                :italic => "/app/fonts/RobotoCondensed-Italic.ttf",
                :bold => "/app/fonts/RobotoCondensed-Bold.ttf",
                :bold_italic => "/app/fonts/RobotoCondensed-BoldItalic.ttf"
            })
            font_families.update("Roboto" => {
                :normal => "/app/fonts/Roboto-Regular.ttf",
                :italic => "/app/fonts/Roboto-Italic.ttf",
                :bold => "/app/fonts/Roboto-Bold.ttf",
                :bold_italic => "/app/fonts/Roboto-BoldItalic.ttf"
            })
            first_page = true
            line_width 0.1.mm
            font('Roboto') do
                klassen_for_shorthands.keys.sort do |a, b|
                    a.downcase <=> b.downcase
                end.each do |shorthand|
                    ZEUGNIS_KLASSEN_ORDER.each do |klasse|
                        next unless klassen_for_shorthands[shorthand].include?(klasse)
                        next if consider_sus_for_klasse[klasse].empty?
                        liste = @@zeugnisliste_for_klasse[klasse]
                        nr_width = 8.mm
                        name_width = 4.cm
                        fach_width = (267.mm - (nr_width + name_width)) / liste[:faecher].size
                        n_klasse = consider_sus_for_klasse[klasse].size
                        n_per_page = 10
                        n_pages = ((n_klasse - 1) / n_per_page).floor + 1
                        page = 0
                        offset = 0
                        while n_klasse > 0 do
                            page += 1
                            start_new_page unless first_page
                            first_page = false
                            font('Roboto') do
                                bounding_box([15.mm, 197.mm], width: 2.5.cm, height: 1.5.cm) do
                                    move_down 4.mm
                                    text "<b>#{Main.tr_klasse(klasse)}</b>", :align => :center, :inline_format => true, :size => 24
                                    stroke_bounds
                                end
                                bounding_box([257.mm, 197.mm], width: 2.5.cm, height: 1.5.cm) do
                                    move_down 4.mm
                                    text "<b>#{shorthand}</b>", :align => :center, :inline_format => true, :size => 24
                                    stroke_bounds
                                end
                                bounding_box([15.mm, 20.mm], width: 200.mm, height: 10.mm) do
                                    line [0.mm, 11.mm], [60.mm, 11.mm]
                                    stroke
                                    text "<sup>1</sup>links oben: allgemeiner Teil, links unten: schriftliche Leistungen, falls abweichend; rechts: Gesamt", :align => :left, :inline_format => true, :size => 10
                                end
                                bounding_box([210.mm, 23.mm], width: 70.mm, height: 15.mm) do
                                    text "<b>VERTRAULICH</b>", :align => :center, :inline_format => true, :size => 24, :valign => :center, :rotate => 5
                                    # stroke_bounds
                                end
                            end
                            bounding_box([15.mm, 210.mm - 13.mm], width: 267.mm, height: 18.cm) do
                                float do
                                    text "<b>Anlage zum Protokoll der Zeugniskonferenz</b>", :align => :center, :inline_format => true
                                    move_down(1.mm)
                                    text "#{ZEUGNIS_HALBJAHR}. Halbjahr, Schuljahr #{ZEUGNIS_SCHULJAHR.gsub('_', '/')}", :align => :center, :inline_format => true
                                    move_down(3.mm)
                                    text "Seite #{page} von #{n_pages}", :align => :center, :inline_format => true
                                end
                            end
                            bounding_box([15.mm, 210.mm - 35.mm], width: 267.mm, height: 15.cm) do
                                n = [n_per_page, n_klasse].min
                                row_height = 15.cm / (n_per_page + 1)

                                (0..n).each do |i|
                                    if i % 2 == 1
                                        rectangle [0.mm, row_height * (n_per_page + 1 - i)], 267.mm, row_height
                                    end
                                end
                                fill_color 'f0f0f0'
                                fill
                                fill_color '000000'

                                (0..(n+1)).each do |i|
                                    line [0.mm, row_height * (11 - i)], [267.mm, row_height * (n_per_page + 1 - i)]
                                end
                                stops = []
                                stops << 0.mm
                                stops << nr_width
                                stops << nr_width + name_width
                                (0..liste[:faecher].size).each do |i|
                                    stops << (nr_width + name_width) + fach_width * i
                                end

                                stops.each do |x|
                                    line [x, row_height * 11], [x, row_height * (n_per_page + 1 - n - 1)]
                                end
                                stroke

                                font('RobotoCondensed') do
                                    bounding_box([0.mm, row_height * (n_per_page + 1)], width: nr_width - 1.mm, height: row_height) do
                                        move_down row_height * 0.5 - 6
                                        text "<b>Nr.</b>", :align => :right, :inline_format => true, :size => 11
                                    end
                                    bounding_box([nr_width + 2.mm, row_height * (n_per_page + 1)], width: name_width - 2.mm, height: row_height) do
                                        move_down row_height * 0.5 - 6
                                        text "<b>Name</b>", :align => :left, :inline_format => true, :size => 11
                                    end
                                    (0...liste[:faecher].size).each do |x|
                                        bounding_box([(nr_width + name_width) + fach_width * x, row_height * (n_per_page + 1)], width: fach_width, height: row_height) do
                                            move_down row_height * 0.5 - 6
                                            fach = liste[:faecher][x]
                                            text "<b>#{fach}</b>#{FAECHER_SPRACHEN.include?(fach) ? '<sup>1</sup>' : ''}", :align => :center, :inline_format => true, :size => 11
                                            # stroke_bounds
                                        end
                                    end
                                    (0...n).each do |i|
                                        j = i + offset
                                        email = consider_sus_for_klasse[klasse][j]
                                        bounding_box([0.mm, row_height * (n_per_page - i)], width: nr_width - 1.mm, height: row_height) do
                                            move_down row_height * 0.5 - 12
                                            text "#{i + offset + 1}.", :align => :right, :inline_format => true, :size => 11
                                            # stroke_bounds
                                        end
                                        bounding_box([nr_width + 2.mm, row_height * (n_per_page - i)], width: name_width - 2.mm, height: row_height) do
                                            move_down row_height * 0.5 - 12
                                            s = "#{@@user_info[email][:last_name]}"
                                            text elide_string(s, name_width - 2.mm, {:size => 11}), :align => :left, :inline_format => true, :size => 11
                                            save_graphics_state do
                                                translate 2.mm, 0.mm
                                                s = "#{@@user_info[email][:official_first_name]}"
                                                text elide_string(s, name_width - 2.mm - 2.mm, {:size => 11}), :align => :left, :inline_format => true, :size => 11
                                            end
                                            # stroke_bounds
                                        end
                                        (0...liste[:faecher].size).each do |x|
                                            fach = liste[:faecher][x]
                                            bounding_box([(nr_width + name_width) + fach_width * x, row_height * (n_per_page - i)], width: fach_width, height: row_height) do
                                                if FAECHER_SPRACHEN.include?(fach)
                                                    line [0, row_height * 0.5], [fach_width * 0.5, row_height * 0.5]
                                                    line [fach_width * 0.5, 0], [fach_width * 0.5, row_height]
                                                    stroke
                                                    bounding_box([0.mm, row_height], width: fach_width / 2, height: row_height / 2) do
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}_AT/Email:#{email}"]
                                                        if note
                                                            float do
                                                                if NOTEN_MARK.include?(note)
                                                                    save_graphics_state do
                                                                        translate(fach_width / 4, row_height / 4)
                                                                        fill_color i % 2 == 0 ? 'f0f0f0' : 'ffffff'
                                                                        fill_circle [0, 0], 11
                                                                        stroke_circle [0, 0], 11
                                                                    end
                                                                end
                                                                text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :size => 11, :final_gap => false, :valign => :center
                                                            end
                                                        end
                                                        # stroke_bounds
                                                    end
                                                    bounding_box([0.mm, row_height / 2], width: fach_width / 2, height: row_height / 2) do
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}_SL/Email:#{email}"]
                                                        if note
                                                            float do
                                                                if NOTEN_MARK.include?(note)
                                                                    save_graphics_state do
                                                                        translate(fach_width / 4, row_height / 4)
                                                                        fill_color i % 2 == 0 ? 'f0f0f0' : 'ffffff'
                                                                        fill_circle [0, 0], 11
                                                                        stroke_circle [0, 0], 11
                                                                    end
                                                                end
                                                                text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :size => 11, :final_gap => false, :valign => :center
                                                            end
                                                        end
                                                        # stroke_bounds
                                                    end
                                                    bounding_box([fach_width / 2, row_height], width: fach_width / 2, height: row_height) do
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"]
                                                        if note
                                                            float do
                                                                if NOTEN_MARK.include?(note)
                                                                    save_graphics_state do
                                                                        translate(fach_width / 4, row_height / 2)
                                                                        fill_color i % 2 == 0 ? 'f0f0f0' : 'ffffff'
                                                                        fill_circle [0, 0], 11
                                                                        stroke_circle [0, 0], 11
                                                                    end
                                                                end
                                                                text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :size => 11, :final_gap => false, :valign => :center
                                                            end
                                                        end
                                                    end
                                                else
                                                    note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"]
                                                    if note
                                                        if NOTEN_MARK.include?(note)
                                                            save_graphics_state do
                                                                translate(fach_width / 2, row_height / 2)
                                                                fill_color i % 2 == 0 ? 'f0f0f0' : 'ffffff'
                                                                fill_circle [0, 0], 11
                                                                stroke_circle [0, 0], 11
                                                            end
                                                        end
                                                        text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :inline_format => true, :size => 11, :valign => :center
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end

                                # float do
                                # end
                                # stroke_bounds
                            end
                            n_klasse -= n_per_page
                            offset += n_per_page
                        end
                    end
                end
            end
        end
        return doc.render
    end

    def get_zeugnislisten_sheets_pdf(cache)
        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :portrait, :margin => 0) do
            font_families.update("RobotoCondensed" => {
                :normal => "/app/fonts/RobotoCondensed-Regular.ttf",
                :italic => "/app/fonts/RobotoCondensed-Italic.ttf",
                :bold => "/app/fonts/RobotoCondensed-Bold.ttf",
                :bold_italic => "/app/fonts/RobotoCondensed-BoldItalic.ttf"
            })
            font_families.update("Roboto" => {
                :normal => "/app/fonts/Roboto-Regular.ttf",
                :italic => "/app/fonts/Roboto-Italic.ttf",
                :bold => "/app/fonts/Roboto-Bold.ttf",
                :bold_italic => "/app/fonts/Roboto-BoldItalic.ttf"
            })
            first_page = true
            line_width 0.1.mm
            font('Roboto') do
                ZEUGNIS_KLASSEN_ORDER.each do |klasse|
                    next unless klasse == '10o'
                    liste = @@zeugnisliste_for_klasse[klasse]
                    nr_width = 10.mm
                    name_width = 66.mm
                    bem_width = 50.mm
                    cols_left_template  = %w(D D_AT D_SL FS1_Fach FS1 FS1_AT FS1_SL FS2_Fach FS2 FS2_AT FS2_SL FS3_Fach FS3 FS3_AT FS3_SL)
                    cols_right_template = %w(Gewi Eth Ek Ge Pb Ma Nawi Ph Ch Bio Ku Mu Sp FF1 . FF2 . FF3 . VT VT_UE VS VS_UE VSP)

                    # missing_faecher = liste[:faecher]
                    # (cols_left + cols_right).each do |x|
                    #     missing_faecher.delete(x)
                    # end
                    # STDERR.puts "#{klasse}: #{missing_faecher.to_json}"

                    lboxwidth = (19.cm - nr_width - name_width) / cols_left_template.size
                    lboxheight = 277.mm / 11 / 4
                    rboxwidth = (19.cm - bem_width) / cols_right_template.size
                    rboxheight = 277.mm / 11 / 4

                    left = BoxPrinter.new(self, nr_width + name_width, 277.mm - lboxheight * 4, lboxwidth, lboxheight)
                    right = BoxPrinter.new(self, 0.0, 277.mm - rboxheight * 4, rboxwidth, rboxheight)

                    n_klasse = liste[:schueler].size
                    n_per_page = 10
                    n_pages = ((n_klasse - 1) / n_per_page).floor + 1
                    offset = 0
                    start_new_page unless first_page
                    first_page = false
                    font('Roboto') do
                        bounding_box([1.5.cm, 287.mm], width: 18.cm, height: 10.cm) do
                            float { text "Gymnasium Steglitz 06Y13", :align => :left }
                            float { text "Steglitz-Zehlendorf", :align => :right }
                        end
                        line [1.5.cm, 280.mm], [19.5.cm, 280.mm]
                        line [1.5.cm, 10.mm], [19.5.cm, 10.mm]
                        stroke
                        bounding_box([2.cm, 260.mm], width: 17.cm, height: 25.cm) do
                            text "<b>Zeugnisliste</b>", :align => :center, :inline_format => true, :size => 24
                            move_down 2.cm
                            text "der", :align => :center, :inline_format => true
                            move_down 1.5.cm
                            text "<b>Klasse #{Main.tr_klasse(klasse)}</b>", :align => :center, :inline_format => true, :size => 16
                            move_down 0.8.cm
                            text "für das Schuljahr #{ZEUGNIS_SCHULJAHR.sub('_', '-')}/#{ZEUGNIS_HALBJAHR}", :align => :center, :inline_format => true, :size => 16
                            move_down 1.5.cm
                            klassenleitung = @@klassenleiter[klasse].map do |shorthand|
                                email = @@shorthands[shorthand]
                                @@user_info[email][:display_name_official]
                            end
                            text "Klassenleitung: #{klassenleitung.join(', ')}", :align => :center, :inline_format => true
                            move_down 7.cm
                            text "Die Zeugnisse wurden erteilt:", :align => :center
                            move_down 1.cm
                            text "1. am #{'_' * 30} #{' ' * 7} #{'_' * 30}", :align => :center
                            float do
                                translate 10.cm, 0 do
                                    @@klassenleiter[klasse].each do |shorthand|
                                        email = @@shorthands[shorthand]
                                        text "Klassenleitung #{@@user_info[email][:display_name_official]}", :align => :left, :size => 7
                                        move_down 7.mm
                                    end
                                end
                            end
                            move_down 5.mm
                            text "2. am #{'_' * 30} #{' ' * 7} #{'_' * 30}", :align => :center
                            move_down 1.cm
                            text "Die allgemeinen Beurteilungen sind auf besonderer Liste beigefügt.", :align => :center, :size => 10
                            move_down 2.mm
                            text "Leistungen: 1 = sehr gut, 2 = gut, 3 = befriedigend, 4 = ausreichend, 5 = mangelhaft, 6 = ungenügend", :align => :center, :size => 10
                            move_down 2.mm
                            text "Es können auch Noten mit Tendenzen eingetragen werden.", :align => :center, :size => 10
                        end
                    end
                    while n_klasse > 0 do
                        [0, 1].each do |side|
                            start_new_page
                            bounding_box([1.cm, 287.mm], width: 19.cm, height: 277.mm) do
                                line_width 0.3.mm
                                stroke_bounds
                                h = 277.mm / 11
                                if side == 0
                                    line_width 0.1.mm
                                    (0...cols_left_template.size).each do |x|
                                        line [nr_width + name_width + lboxwidth * x, 0.0], [nr_width + name_width + lboxwidth * x, 277.mm - h / 4.0]
                                    end
                                    line [nr_width + name_width, 277.mm - h / 4.0, 19.cm, 277.mm - h / 4.0]
                                    stroke
                                    line_width 0.3.mm
                                    line [nr_width, 0.0], [nr_width, 277.mm]
                                    line [nr_width + name_width, 0.0], [nr_width + name_width, 277.mm]
                                    line [nr_width + name_width + lboxwidth * 3, 0.0], [nr_width + name_width + lboxwidth * 3, 277.mm]
                                    (1..2).each do |x|
                                        line [nr_width + name_width + lboxwidth * 3 + lboxwidth * 4 * x, 0.0], [nr_width + name_width + lboxwidth * 3 + lboxwidth * 4 * x, 277.mm]
                                    end
                                    stroke
                                    font('RobotoCondensed') do
                                        bounding_box([2.mm, h * 10.6], width: nr_width - 2.mm, height: h / 4.0) do
                                            text "Nr.", :valign => :center, :size => 11
                                        end
                                        bounding_box([nr_width + 2.mm, h * 10.6], width: name_width - 2.mm, height: h / 4.0) do
                                            text "Name, Vorname und Geburtstag", :valign => :center, :size => 11
                                        end
                                        left.print(0, -4, 'Deutsch', :width => 3)
                                        left.print(3, -4, '1. Fremdsprache', :width => 4)
                                        left.print(7, -4, '2. Fremdsprache', :width => 4)
                                        left.print(11, -4, '3. Fremdsprache', :width => 4)
                                        cols_left_template.each.with_index do |f, i|
                                            s = "#{f}"
                                            s = '' if s == '.'
                                            s = 'AT' if s[-3, 3] == '_AT'
                                            s = 'SL' if s[-3, 3] == '_SL'
                                            s = 'ges' if ['FS1', 'FS2', 'FS3', 'D', 'En', 'La', 'Agr', 'Fr'].include?(s)
                                            s = '' if s[-5, 5] == '_Fach'
                                            left.print(i, -3, s)
                                            translate 2.mm, -3.mm do
                                                left.print(i, -1, (liste[:lehrer_for_fach][f] || []).join(', '), :rotate => 90, :align => :left, :width => 2)
                                            end
                                        end
                                    end
                                elsif side == 1
                                    line_width 0.1.mm
                                    (1..24).each do |x|
                                        line [rboxwidth * x, 0.0], [rboxwidth * x, 277.mm - h / 4.0]
                                    end
                                    line [0.mm, 277.mm - h / 4.0, 19.cm - bem_width, 277.mm - h / 4.0]
                                    stroke
                                    line_width 0.3.mm
                                    [5, 6, 10, 11, 12, 13, 15, 17, 19, 24].each do |k|
                                        line [rboxwidth * k, 0.0], [rboxwidth * k, 277.mm]
                                    end
                                    line [rboxwidth * 21, 0.0], [rboxwidth * 21, 277.mm - rboxheight]
                                    line [rboxwidth * 23, 0.0], [rboxwidth * 23, 277.mm - rboxheight]
                                    stroke
                                    font('RobotoCondensed') do
                                        right.print(0, -4, 'Gesellschaftswiss.', :width => 5)
                                        right.print(6, -4, 'Naturwiss.', :width => 4)
                                        right.print(19, -4, 'Versäumnisse', :width => 5)
                                        cols_right_template.each.with_index do |f, i|
                                            s = "#{f}"
                                            s = '' if s == '.'
                                            s = 'AT' if s[-3, 3] == '_AT'
                                            s = 'SL' if s[-3, 3] == '_SL'
                                            s = 'ges' if ['Gewi', 'Nawi'].include?(s)
                                            if %w(VT VT_UE VS VS_UE VSP).include?(f)
                                                translate 1.4.mm, -3.mm do
                                                    right.print(i, -1, {'VT' => 'Tage', 'VT_UE' => 'unentsch.', 'VS' => 'Stunden', 'VS_UE' => 'unentsch.', 'VSP' => 'Versp.'}[s], :rotate => 90, :align => :left, :width => 3)
                                                end
                                            elsif %w(Ma Ku Mu Sp).include?(f)
                                                right.print(i, -4, s)
                                            elsif %w(FF1 FF2 FF3).include?(f)
                                                right.print(i, -4, "Freies Fach #{f.gsub('F', '')}", :width => 2)
                                            else
                                                right.print(i, -3, s)
                                            end
                                            translate 1.4.mm, -3.mm do
                                                right.print(i, -1, (liste[:lehrer_for_fach][f] || []).join(', '), :rotate => 90, :align => :left, :width => 2)
                                            end
                                        end
                                    end
                                end
                                (1..10).each do |y|
                                    i = 10 - y + offset
                                    y2 = 10 - y
                                    schueler = liste[:schueler][i]
                                    next if schueler.nil?
                                    cols_left = cols_left_template.map do |x2|
                                        x = "#{x2}"
                                        if schueler[:zeugnis_key].include?('sesb')
                                            x.gsub!('FS1', 'Ngr')
                                            x.gsub!('FS2', 'En')
                                            x.gsub!('FS3', 'Fr')
                                        else
                                            x.gsub!('FS1', 'En')
                                            x.gsub!('FS2', 'La')
                                            x.gsub!('FS3', 'Agr')
                                        end
                                        x
                                    end
                                    STDERR.puts "#{schueler[:email]} #{cols_left.to_json}"
                                    cols_right = cols_right_template.map { |x| x }
                                    line_width 0.3.mm
                                    line [0.0, h * y], [19.cm, h * y]
                                    stroke
                                    (1..3).each do |sy|
                                        line_width 0.1.mm
                                        line [0.0, h * (y - sy / 4.0)], [19.cm, h * (y - sy / 4.0)]
                                        stroke
                                    end
                                    email = schueler[:email]
                                    font('RobotoCondensed') do
                                        if side == 0
                                            bounding_box([2.mm, h * y], width: nr_width - 4.mm, height: h / 4.0) do
                                                text "#{y2 + offset + 1}.", :align => :right, :valign => :center, :size => 11
                                            end
                                            bounding_box([nr_width + 2.mm, h * y], width: name_width - 2.mm, height: h / 4.0) do
                                                text "#{elide_string(schueler[:last_name], name_width - 2.mm)}", :valign => :center, :size => 11
                                            end
                                            bounding_box([nr_width + 7.mm, h * (y - 0.25)], width: name_width - 7.mm, height: h / 4.0) do
                                                text "#{elide_string(schueler[:official_first_name], name_width - 7.mm)}", :valign => :center, :size => 11
                                            end
                                            bounding_box([nr_width + 2.mm, h * (y - 0.5)], width: name_width - 4.mm, height: h / 4.0) do
                                                text "#{elide_string(Date.parse(schueler[:geburtstag]).strftime('%d.%m.%Y'), name_width - 6.mm)}", :valign => :center, :align => :right, :size => 11
                                            end
                                            bounding_box([nr_width + 2.mm, h * (y - 0.75)], width: name_width - 2.mm, height: h / 4.0) do
                                                if schueler[:zeugnis_key].include?('sesb')
                                                    text "#{elide_string('Fs-Folge: Neugriechisch – Englisch – Französisch', name_width - 2.mm, {:size => 9})}", :valign => :center, :size => 9
                                                else
                                                    text "#{elide_string('Fs-Folge: Englisch – Latein – Altgriechisch', name_width - 2.mm, {:size => 10})}", :valign => :center, :size => 10
                                                end
                                            end
                                            font('Roboto') do
                                                cols_left.each.with_index do |f, i|
                                                    if f[-5, 5] == '_Fach'
                                                        left.print(i, y2 * 4 + 3, "#{f.sub('_Fach', '')}")
                                                    else
                                                        left.print(i, y2 * 4 + 3, cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{f}/Email:#{email}"])
                                                    end
                                                end
                                            end
                                        elsif side == 1
                                            font('Roboto') do
                                                cols_right.each.with_index do |f, i|
                                                    right.print(i, y2 * 4 + 3, cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{f}/Email:#{email}"])
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        n_klasse -= n_per_page
                        offset += n_per_page
                    end
                    start_new_page
                end
            end
        end
        return doc.render
    end
end

