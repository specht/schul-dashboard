require 'prawn'
require 'prawn/measurement_extensions'
require 'prawn-styled-text'
require '/app/include/color.rb'
require '/app/include/color-schemes.rb'

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

    def print_note(x, y, v, v_prev)
        print(x, y, v)
        if v != v_prev
            left = @left + x * @width + @width * 0.2
            top = @top - y * @height
            @pdf.fill_color 'ffffff'
            @pdf.fill_circle([left, top], 6)
            @pdf.fill_color '000000'
            @pdf.stroke_circle([left, top], 6)
            d = 1.5.mm
            @pdf.line([left - d, top - d], [left + d, top + d])
            @pdf.stroke
            @pdf.translate -@width * 0.3, @height * 0.5 do
                print(x, y, "<b>#{v_prev}</b>", :size => 6)
            end
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
                first_name = "#{schueler[:official_first_name]}"
                last_name = "#{schueler[:last_name]}"
                liste[:faecher].each do |fach|
                    sub_faecher = [fach]
                    if FAECHER_SPRACHEN.include?(fach)
                        sub_faecher << "#{fach}_AT"
                        sub_faecher << "#{fach}_SL"
                    end
                    sub_faecher.each do |sub_fach|
                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{sub_fach}/Email:#{email}"][0]
                        if NOTEN_MARK.include?(note)
                            consider_sus_for_klasse[klasse] << email
                        end
                    end
                end
                zk_marked = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/ZK:marked/Email:#{email}"][0]
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
            page = 0
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
                        kpage = 0
                        n_per_page = 10
                        n_pages = ((n_klasse - 1) / n_per_page).floor + 1
                        offset = 0
                        while n_klasse > 0 do
                            page += 1
                            kpage += 1
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
                                    text "Seite #{kpage} von #{n_pages}", :align => :center, :inline_format => true
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
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}_AT/Email:#{email}"][0]
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
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}_SL/Email:#{email}"][0]
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
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"][0]
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
                                                    note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"][0]
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
                    if page % 2 != 0
                        page += 1
                        start_new_page
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
                    # next unless klasse == '10o'
                    liste = @@zeugnisliste_for_klasse[klasse].clone

                    cols_left_template  = %w(D D_AT D_SL FS1_Fach FS1 FS1_AT FS1_SL FS2_Fach FS2 FS2_AT FS2_SL FS3_Fach FS3 FS3_AT FS3_SL)
                    cols_right_template = %w(Gewi Eth Ek Ge Pb Ma Nawi Ph Ch Bio Ku Mu Sp FF1 . FF2 . FF3 . VT VT_UE VS VS_UE VSP)

                    faecher_for_fs = {
                        1 => Set.new(),
                        2 => Set.new(),
                        3 => Set.new()
                    }
                    wahlfaecher = Set.new()
                    # determine lehrer for FS1, FS2, FS3
                    liste[:schueler].each do |schueler|
                        fs = []
                        if schueler[:zeugnis_key].include?('sesb')
                            fs << 'Ngr'
                            fs << 'En'
                            fs << 'Fr'
                        else
                            fs << 'En'
                            fs << 'La'
                            fs << 'Agr' if klasse.to_i >= 8
                        end
                        faecher_for_fs[1] << fs[0]
                        faecher_for_fs[2] << fs[1]
                        faecher_for_fs[3] << fs[2] if fs[2]
                        handled_faecher = Set.new(cols_left_template) | Set.new(cols_right_template)
                        handled_faecher |= Set.new(fs)
                        liste[:faecher].each do |fach|
                            if liste[:wahlfach][fach]
                                v = (cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{schueler[:email]}"] || [])[0]
                                if v && v != '×'
                                    unless handled_faecher.include?(fach)
                                        wahlfaecher << fach
                                    end
                                end
                            end
                        end
                    end

                    extra_wahlfach_count = 0
                    if wahlfaecher.size > 3
                        extra_wahlfach_count = wahlfaecher.size - 3
                        (0...extra_wahlfach_count).to_a.reverse.each do |i|
                            cols_right_template.insert(19, '.')
                            cols_right_template.insert(19, "FF#{i + 4}")
                        end
                    end

                    wahlfaecher = wahlfaecher.to_a

                    faecher_for_fs = Hash[faecher_for_fs.map { |k, v| [k, v.to_a.sort] }]
                    (1..3).each do |i|
                        liste[:lehrer_for_fach]["FS#{i}"] = faecher_for_fs[i].map do |x|
                            "#{liste[:lehrer_for_fach][x].join(' ')} (#{x})"
                        end
                    end

                    nr_width = 10.mm
                    name_width = 66.mm
                    bem_width = 50.mm

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
                                            f2 = f.clone
                                            if ['FS1', 'FS2', 'FS3'].include?(f)
                                                f2 = ''
                                            end
                                            if f.include?('_Fach')
                                                f2 = f.sub('_Fach', '')
                                            end
                                            translate 2.mm, -3.mm do
                                                if ['FS1', 'FS2', 'FS3'].include?(f2)
                                                    diff = (liste[:lehrer_for_fach][f2] || []).size == 1 ? [0, 0] : [-1.mm, -1.mm]
                                                    translate *diff do
                                                        left.print(i, -1, (liste[:lehrer_for_fach][f2] || []).join("\n"), :rotate => 90, :align => :left, :width => 2)
                                                    end
                                                else
                                                    left.print(i, -1, (liste[:lehrer_for_fach][f2] || []).join(', '), :rotate => 90, :align => :left, :width => 2)
                                                end
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
                                    # [5, 6, 10, 11, 12, 13, 15, 17, 19, 24].each do |k|
                                    [5, 6, 10, 11, 12, 13, 13 + (3 + extra_wahlfach_count) * 2 + 5].each do |k|
                                        line [rboxwidth * k, 0.0], [rboxwidth * k, 277.mm]
                                    end
                                    (0..(3 + extra_wahlfach_count)).each do |i|
                                        k = i * 2 + 13
                                        line [rboxwidth * k, 0.0], [rboxwidth * k, 277.mm]
                                    end
                                    line [rboxwidth * (21 + extra_wahlfach_count * 2), 0.0], [rboxwidth * (21 + extra_wahlfach_count * 2), 277.mm - rboxheight]
                                    line [rboxwidth * (23 + extra_wahlfach_count * 2), 0.0], [rboxwidth * (23 + extra_wahlfach_count * 2), 277.mm - rboxheight]
                                    stroke
                                    font('RobotoCondensed') do
                                        right.print(0, -4, 'Gesellschaftswiss.', :width => 5)
                                        right.print(6, -4, 'Naturwiss.', :width => 4)
                                        right.print(19 + extra_wahlfach_count * 2, -4, 'Versäumnisse', :width => 5)
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
                                            elsif %w(FF1 FF2 FF3 FF4 FF5 FF6).include?(f)
                                                right.print(i, -4, "Freies Fach #{f.gsub('F', '')}", :width => 2)
                                                wf = wahlfaecher[f.sub('FF', '').to_i - 1]
                                                right.print(i, -3, wf)
                                                translate 1.4.mm, -3.mm do
                                                    right.print(i, -1, (liste[:lehrer_for_fach][wf] || []).join(', '), :rotate => 90, :align => :left, :width => 2)
                                                end
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
                                    line_width 0.3.mm
                                    line [0.0, h * y], [19.cm, h * y]
                                    stroke
                                    (1..3).each do |sy|
                                        line_width 0.1.mm
                                        line [0.0, h * (y - sy / 4.0)], [19.cm, h * (y - sy / 4.0)]
                                        stroke
                                    end
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
                                            if klasse.to_i >= 8
                                                x.gsub!('FS3', 'Agr')
                                            else
                                                x.gsub!('FS3', '')
                                            end
                                        end
                                        x
                                    end
                                    # STDERR.puts "#{schueler[:email]} #{cols_left.to_json}"
                                    cols_right = cols_right_template.map { |x| x }
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
                                                        v = (cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{f}/Email:#{email}"] || [])[0]
                                                        v_prev = (cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{f}/Email:#{email}"] || [])[1]
                                                        left.print_note(i, y2 * 4 + 3, v, v_prev)
                                                    end
                                                end
                                            end
                                        elsif side == 1
                                            font('Roboto') do
                                                cols_right.each.with_index do |f, i|
                                                    f2 = f.dup
                                                    if %w(FF1 FF2 FF3 FF4 FF5 FF6).include?(f)
                                                        f2 = wahlfaecher[f.sub('FF', '').to_i - 1]
                                                    end
                                                    v = (cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{f2}/Email:#{email}"] || [])[0]
                                                    v_prev = (cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{f2}/Email:#{email}"] || [])[1]
                                                    right.print_note(i, y2 * 4 + 3, v, v_prev)
                                                end
                                                ['VT', 'VT_UE', 'VS', 'VS_UE', 'VSP'].each.with_index do |item, i|
                                                    value = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fehltage:#{item}/Email:#{email}"][0]
                                                    value = '' if value == '0' || value.nil?
                                                    right.print(19 + i, y2 * 4 + 3, value)
                                                end
                                                font('RobotoCondensed') do
                                                    bounding_box([cols_right_template.size * rboxwidth + 1.mm, h * y], width: bem_width - 2.mm, height: h / 4.0) do
                                                        text "#{elide_string(schueler[:last_name] + ', ' + schueler[:official_first_name], bem_width - 2.mm)}", :valign => :center, :size => 11
                                                    end
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

    def get_sozialzeugnis_pdf(klasse, cache, use_png_addition)
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
            font_families.update("AlegreyaSans" => {
                :normal => "/app/fonts/AlegreyaSans-Regular.ttf",
                :italic => "/app/fonts/AlegreyaSans-Italic.ttf",
                :bold => "/app/fonts/AlegreyaSans-Bold.ttf",
                :bold_italic => "/app/fonts/AlegreyaSans-BoldItalic.ttf"
            })
            first_page = true
            line_width 0.1.mm
            liste = @@zeugnisliste_for_klasse[klasse]
            liste[:schueler].each do |schueler|
                email = schueler[:email]
                start_new_page unless first_page
                faecher = liste[:faecher].clone
                faecher << '_KL'
                faecher.reject! do |fach|
                    flag = true
                    SOZIALNOTEN_CATS.each.with_index do |cat, cat_index|
                        item = cat[0]
                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/SV:#{item}/Fach:#{fach}/Email:#{email}"]
                        if ['++', '+', 'o', '-'].include?(note)
                            flag = false
                        end
                    end
                    flag
                end
                first_page = false
                mark_width = 4.cm
                w = (18.cm - mark_width) / faecher.size
                hh = 5.mm
                h = 5.mm
                bounding_box([15.mm, 297.mm - 15.mm], :width => 18.cm, :height => 267.mm) do
                    font('AlegreyaSans') do
                        image "/data/gyst.jpg", :at => [0, 267.mm], :width => 2.5.cm
                        image "/data/sesb.jpg", :at => [16.2.cm, 267.mm], :width => 1.8.cm
                        move_down 2.mm
                        text "Gymnasium Steglitz", :size => 24, :align => :center
                        text "Anlage zum Arbeits- und Sozialverhalten", :align => :center
                        line [0, 2.1.mm], [3.cm, 2.1.mm]
                        float do
                            bounding_box([1.mm, 2.mm], :width => 10.cm, :height => 4.mm) do
                                # stroke_bounds
                                text "<sup>1</sup> Klassenleitung", :inline_format => true, :size => 8
                            end
                        end
                        stroke
                        move_down 7.mm
                        float do
                            move_up 3.mm
                            last_name_parts = schueler[:last_name].split(',').map { |x| x.strip }.reverse
                            name = "#{schueler[:official_first_name]} #{last_name_parts.join(' ')}"
            
                            text "für <b>#{name}</b><br />Klasse #{Main.tr_klasse(klasse)}", :size => 13, :inline_format => true, :align => :center
                        end
                        float do
                            move_down 2.5.mm
                            text "Schuljahr #{ZEUGNIS_SCHULJAHR.sub('_', '/')}", :size => 13, :align => :right
                        end

                        move_down 5.mm

                        SOZIALNOTEN_CATS.each.with_index do |cat, cat_index|
                            move_down 3.mm
                            text "<b>#{cat[1]}</b>", :inline_format => true, :size => 13
                            move_down 1.mm
                            s = "#{cat[2]}"
                            s.gsub!('Die Schülerin / Der Schüler', schueler[:official_first_name])
                            s.gsub!('Sie / Er', schueler[:geschlecht] == 'w' ? 'Sie' : 'Er')
                            s.gsub!('ihre / seine', schueler[:geschlecht] == 'w' ? 'ihre' : 'seine')
                            text s, :size => 11
                            move_down 1.mm
                            bounding_box([0, cursor], :width => 18.cm, :height => hh + 4 * h) do
                                # stroke_bounds
                                (0..4).each do |y|
                                    line [0, y * h], [18.cm, y * h]
                                end
                                line [0, hh + 4 * h], [18.cm, hh + 4 * h]
                                line [0, 0], [0, hh + 4 * h]
                                line [mark_width + faecher.size * w, 0], [mark_width + faecher.size * w, hh + 4 * h]
                                stroke
                                (0...faecher.size).each do |x|
                                    fach = faecher[x]
                                    line [mark_width + x * w, 0], [mark_width + x * w, hh + 4 * h]
                                    stroke
                                    bounding_box([mark_width + x * w, h * 4 + hh], :width => w, :height => hh) do
                                        # stroke_bounds
                                        move_up 0.5.mm
                                        text "#{fach.sub('_KL', 'KL<sup>1</sup>')}", :size => 11, :valign => :center, :align => :center, :inline_format => true
                                    end
                                    item = cat[0]
                                    note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/SV:#{item}/Fach:#{fach}/Email:#{email}"]
                                    # STDERR.puts "[#{note}]"
                                    y = -1
                                    y = 3 if note == '++'
                                    y = 2 if note == '+'
                                    y = 1 if note == 'o'
                                    y = 0 if note == '-'
                                    if y >= 0
                                        bounding_box([mark_width + x * w, h * (y + 1)], :width => w, :height => h) do
                                            # stroke_bounds
                                            move_up 1.mm
                                            text "×", :size => 13, :valign => :center, :align => :center, :inline_format => true
                                        end
                                    end
                                end
                                SOZIALNOTEN_MARKS.reverse.each.with_index do |mark, y|
                                    bounding_box([0.0, (y + 1) * h], :width => 18.cm, :height => h) do
                                        # stroke_bounds
                                    end
                                    bounding_box([1.mm, (y + 1) * h], :width => mark_width, :height => h) do
                                        move_up 0.5.mm
                                        text "…#{mark[1]}", :size => 11, :valign => :center, :align => :left
                                    end
                                end
                            end
                        end
                        bounding_box([18.cm / 4 * 0, 1.2.cm], :width => 18.cm / 4, :height => 1.cm) do
                            text "Berlin, den #{ZEUGNIS_DATUM}", :size => 11
                        end
                        ['Klassenleitung', 'Schulleitung', 'Kenntnis genommen:<br />Erziehungsberechtige/r'].each.with_index do |x, i|
                            bounding_box([18.cm / 4 * (i + 1), 1.2.cm], :width => 18.cm / 4 * 0.9, :height => 1.5.cm) do
                                line [0, 9.5.mm], [18.cm / 4 * 0.9, 9.5.mm]
                                stroke
                                move_down 6.mm
                                float do
                                    text x, :size => 11, :align => :center, :inline_format => true
                                end
                            end
                        end
                    end
                end
            end
        end
        return doc.render
    end

    def get_single_timetable_pdf(email, color_scheme, use_png_addition)
        today = Time.now.strftime('%Y-%m-%d')
        if today < @@config[:first_school_day]
            today = @@config[:first_school_day]
        end
        klasse = @@user_info[email][:klasse]
        display_name = @@user_info[email][:display_name]
        d = @@lessons[:start_date_for_date][today]
        timetable = {}
        max_stunden = 1
        @@lessons[:timetables][d].each_pair do |lesson_key, lesson_info|
            lesson_info[:stunden].each_pair do |day, stunden|
                stunden.each_pair do |stunde, info|
                    if info[:klassen].include?(klasse)
                        if @@lessons_for_user[email].include?(lesson_key)
                            timetable[day] ||= {}
                            x = info.clone
                            x[:lesson_key] = lesson_key
                            timetable[day][stunde] ||= []
                            timetable[day][stunde] << x
                            max_stunden = stunde if stunde > max_stunden
                        end
                    end
                end
            end
        end
        # STDERR.puts timetable.to_yaml
        hours_key = HOURS_FOR_KLASSE.keys.reject do |x|
            today < x
        end.max

        hours = HOURS_FOR_KLASSE[hours_key][klasse]
        _self = self

        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :landscape, :margin => 0) do
            font_families.update("myfont" => {
                :normal => "/app/fonts/AlegreyaSans-Regular.ttf",
                :bold => "/app/fonts/AlegreyaSans-Bold.ttf",
                # :normal => "/app/fonts/Pacifico-Regular.ttf",
                # :bold => "/app/fonts/Pacifico-Regular.ttf",
                # :normal => "/app/fonts/Signika-Regular.ttf",
                # :bold => "/app/fonts/Signika-Bold.ttf",
                # :normal => "/app/fonts/LilitaOne-Regular.ttf",
            })
            # fscale = 1.0
            # dx = 0
            # dy = 0
            fscale = 0.85 # 0.95
            dx = 0.mm
            dy = 0.3.mm
            bs = 1.3
            scale -1, :origin => [297.mm / 2, 210.mm / 2] do
                image("/gen/bg/bg-#{color_scheme}.jpg", :at => [-297.mm * (bs - 1.0) * 0.5, 210.mm], :width => 297.mm * bs, :height => 210.mm * bs)
            end
            image("/app/images/timetable-back-light.png", :at => [0, 210.mm], :width => 297.mm, :height => 210.mm)

            # STDERR.puts COLOR_SCHEME_COLORS.to_yaml
            # exit
            palette = _self.color_palette_for_color_scheme(color_scheme)
            # STDERR.puts palette.to_yaml
            col1 = palette[:primary]
            col2 = palette[:primary_color_darker]
            textcol = palette[:main_text]
            
            font('myfont') do
                move_down 10.mm
                float do
                    translate dx, dy do
                        fill_color 'ffffff'
                        stroke_color 'ffffff'
                        text_rendering_mode(:stroke) do
                            line_width 1.mm
                            text('<b>Stundenplan</b>', :align => :center, :size => 36 * fscale, :inline_format => true)
                        end
                    end
                end
                fill_color color_scheme[0] == 'l' ? '222222' : 'eeeeee'
                float do
                    translate dx, dy do
                        text_rendering_mode(:fill) do
                            text('<b>Stundenplan</b>', :align => :center, :size => 36 * fscale, :inline_format => true)
                        end
                    end
                end
                move_down 1.2.cm
                float do
                    translate dx, dy do
                        fill_color 'ffffff'
                        stroke_color 'ffffff'
                        text_rendering_mode(:stroke) do
                            line_width 1.mm
                            text("#{display_name} (#{Main.tr_klasse(klasse)})", :align => :center, :size => 18 * fscale)
                        end
                    end
                end
                fill_color color_scheme[0] == 'l' ? '222222' : 'eeeeee'
                float do
                    translate dx, dy do
                        text_rendering_mode(:fill) do
                            text("#{display_name} (#{Main.tr_klasse(klasse)})", :align => :center, :size => 18 * fscale)
                        end
                    end
                end
                fill_color '222222'
                left = 22.mm
                bottom = 25.mm
                width = 254.mm
                height = 140.mm
                tw = 30.mm
                w = (width - tw) / 5.0
                h = height / (max_stunden + 1)
                line_width 0.1.mm
                bounding_box([left, bottom + height], :width => width, :height => height) do
                    # line [0.0, 0.0], [0.0, height]
                    # (0..5).each do |x|
                    #     line [tw + w * x, 0.0], [tw + w * x, height]
                    #     stroke
                    # end
                    # (0..(max_stunden + 1)).each do |y|
                    #     line [0.0, h * y], [width, h * y]
                    #     stroke
                    # end
                    # bounding_box([0.0, height], :width => tw, :height => h) do
                    #     rounded_rectangle([1.mm, h - 1.mm], tw - 2.mm, h - 2.mm, 2.mm)
                    #     fill_color 'fad31c'
                    #     fill
                    #     fill_color '222222'
                    #     text_box "<b>Stunde</b>", :at => [3.mm, h - 1.mm], :width => tw - 6.mm, :height => h - 2.mm, :align => :left, :valign => :center, :size => 18, :overflow => :shrink_to_fit, :inline_format => true
                    # end
                    %w(Montag Dienstag Mittwoch Donnerstag Freitag).each.with_index do |s, x|
                        bounding_box([tw + x * w, height], :width => w, :height => h) do
                            rounded_rectangle([0.5.mm, h - 0.5.mm], w - 1.mm, h - 1.mm, 2.mm)
                            # fill_color palette[:primary_color_much_lighter][1, 6]
                            # stroke_color palette[:primary][1, 6]
                            fill_color 'ffffff'
                            stroke_color 'aaaaaa'
                            fill_and_stroke
                            # fill
                            fill_color '222222'
                            translate dx, dy do
                                text_box "<b>#{s}</b>", :at => [3.mm, h - 1.mm], :width => w - 6.mm, :height => h - 2.mm, :align => :center, :valign => :center, :size => 18 * fscale, :overflow => :shrink_to_fit, :inline_format => true
                            end
                        end
                    end
                    (1..max_stunden).each do |y|
                        bounding_box([0.0, height - y * h], :width => tw, :height => h) do
                            # stroke_bounds
                            rounded_rectangle([0.5.mm, h - 0.5.mm], tw - 1.mm, h - 1.mm, 2.mm)
                            # fill_color palette[:primary_color_much_lighter][1, 6]
                            # stroke_color palette[:primary][1, 6]
                            fill_color 'ffffff'
                            stroke_color 'aaaaaa'

                            fill_and_stroke
                            fill_color '222222'
                            text_box "<b>#{y}. Stunde</b>", :at => [1.mm, h - 1.mm], :width => tw - 2.mm, :height => h / 2, :align => :center, :valign => :bottom, :size => 16 * fscale, :overflow => :shrink_to_fit, :inline_format => true
                            text_box "#{hours[y][0]} – #{hours[y][1]}", :at => [1.mm, h / 2 - 1.mm], :width => tw - 2.mm, :height => h / 2 - 2.mm, :align => :center, :valign => :top, :size => 14 * fscale, :overflow => :shrink_to_fit
                        end
                        (0..4).each do |x|
                            info = (timetable[x] || {})[y]
                            if info
                                bounding_box([tw + x * w, height - y * h], :width => w, :height => h) do
                                    # stroke_bounds
                                    transparent(0.5, 0.5) do
                                        rounded_rectangle([0.5.mm, h - 0.5.mm], w - 1.mm, h - 1.mm, 2.mm)
                                        # fill_color palette[:primary_color_much_lighter][1, 6]
                                        # stroke_color palette[:primary][1, 6]
                                        fill_color 'ffffff'
                                        stroke_color 'aaaaaa'
                                        fill_and_stroke
                                    end
                                    fill_color '222222'
                                    faecher = []
                                    rooms = []
                                    info.each do |x|
                                        lesson_key = x[:lesson_key]
                                        fach = @@lessons[:lesson_keys][lesson_key][:fach]
                                        fach = @@faecher[fach] || fach
                                        fach.gsub!('Sport Jungen', 'Sport')
                                        fach.gsub!('Sport Mädchen', 'Sport')
                                        fach.gsub!('Evangelische Religionslehre', 'Religion')
                                        fach.gsub!('Katholische Religionslehre', 'Religion')
                                        fach.gsub!('Informationstechnischer Grundkurs', 'ITG')
                                        fach.gsub!('Politische Bildung', 'Politik')
                                        fach.gsub!('Gesellschaftswissenschaften', 'Gewi')
                                        fach.gsub!('Naturwissenschaften', 'Nawi')
                                        fach.gsub!('Streicher Anfänger', 'AGs')
                                        fach.gsub!('Basketball', 'AGs')
                                        fach.gsub!('Schach', 'AGs')
                                        fach.gsub!('Unterstufenorchester', 'AGs')
                                        fach.gsub!('AG Garten', 'AGs')
                                        fach.gsub!('BlblA', 'AGs')
                                        fach.gsub!('neugriechisch', 'ngr')
                                        fach.gsub!('(ngr)', '')
                                        fach.gsub!('Partnersprache', 'PS')
                                        fach.strip!
                                        faecher << fach
                                        rooms << x[:raum] unless fach == 'AGs'
                                    end
                                    translate dx, dy do
                                        text_box "<b>#{faecher.uniq.join("\n")}</b>", :at => [3.mm, h - 1.mm], :width => w - 13.mm, :height => h - 2.mm, :align => :left, :valign => :center, :size => 16 * fscale, :overflow => :shrink_to_fit, :inline_format => true
                                        text_box "#{rooms.join("\n")}", :at => [3.mm, h - 1.mm], :width => w - 6.mm, :height => h - 2.mm, :align => :right, :valign => :center, :size => 14 * fscale, :overflow => :shrink_to_fit, :inline_format => true
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if use_png_addition
                image('/app/images/timetable1-front.png', :at => [0, 210.mm], :width => 297.mm, :height => 210.mm)
            end
        end
        return doc.render
    end

    def get_timetables_pdf(klasse, colors)
        today = Time.now.strftime('%Y-%m-%d')
        if today < @@config[:first_school_day]
            today = @@config[:first_school_day]
        end
        # STDERR.puts @@lessons.keys.to_yaml
        d = @@lessons[:start_date_for_date][today]
        timetable = {}
        max_stunden = 1
        @@lessons[:timetables][d].each_pair do |lesson_key, lesson_info|
            lesson_info[:stunden].each_pair do |day, stunden|
                stunden.each_pair do |stunde, info|
                    if info[:klassen].include?(klasse)
                        timetable[day] ||= {}
                        x = info.clone
                        x[:lesson_key] = lesson_key
                        timetable[day][stunde] ||= []
                        timetable[day][stunde] << x
                        max_stunden = stunde if stunde > max_stunden
                    end
                end
            end
        end
        # STDERR.puts timetable.to_yaml
        hours_key = HOURS_FOR_KLASSE.keys.reject do |x|
            today < x
        end.max

        hours = HOURS_FOR_KLASSE[hours_key][klasse]
        _self = self

        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :landscape, :margin => 0) do
            font_families.update("myfont" => {
                :normal => "/app/fonts/AlegreyaSans-Regular.ttf",
                :bold => "/app/fonts/AlegreyaSans-Bold.ttf",
                # :normal => "/app/fonts/Pacifico-Regular.ttf",
                # :bold => "/app/fonts/Pacifico-Regular.ttf",
                # :normal => "/app/fonts/Signika-Regular.ttf",
                # :bold => "/app/fonts/Signika-Bold.ttf",
                # :normal => "/app/fonts/LilitaOne-Regular.ttf",
            })
            # fscale = 1.0
            # dx = 0
            # dy = 0
            fscale = 0.95
            dx = 0.mm
            dy = 0.3.mm
            bs = 1.3
            colors.each.with_index do |color_scheme, index|
                start_new_page if index > 0
                scale -1, :origin => [297.mm / 2, 210.mm / 2] do
                    image("/gen/bg/bg-#{color_scheme}.jpg", :at => [-297.mm * (bs - 1.0) * 0.5, 210.mm], :width => 297.mm * bs, :height => 210.mm * bs)
                end
                image("/app/images/timetable-back-light.png", :at => [0, 210.mm], :width => 297.mm, :height => 210.mm)

                # STDERR.puts COLOR_SCHEME_COLORS.to_yaml
                # exit
                palette = _self.color_palette_for_color_scheme(color_scheme)
                # STDERR.puts palette.to_yaml
                col1 = palette[:primary]
                col2 = palette[:primary_color_darker]
                textcol = palette[:main_text]
                
                fill_color color_scheme[0] == 'l' ? '222222' : 'eeeeee'
                font('myfont') do
                    move_down 10.mm
                    translate dx, dy do
                        text('<b>Stundenplan</b>', :align => :center, :size => 36 * fscale, :inline_format => true)
                    end
                    # move_up 3.mm
                    translate dx, dy do
                        text("Klasse #{Main.tr_klasse(klasse)}", :align => :center, :size => 18 * fscale)
                    end
                    fill_color '222222'
                    left = 22.mm
                    bottom = 25.mm
                    width = 254.mm
                    height = 140.mm
                    tw = 30.mm
                    w = (width - tw) / 5.0
                    h = height / (max_stunden + 1)
                    line_width 0.1.mm
                    bounding_box([left, bottom + height], :width => width, :height => height) do
                        # line [0.0, 0.0], [0.0, height]
                        # (0..5).each do |x|
                        #     line [tw + w * x, 0.0], [tw + w * x, height]
                        #     stroke
                        # end
                        # (0..(max_stunden + 1)).each do |y|
                        #     line [0.0, h * y], [width, h * y]
                        #     stroke
                        # end
                        # bounding_box([0.0, height], :width => tw, :height => h) do
                        #     rounded_rectangle([1.mm, h - 1.mm], tw - 2.mm, h - 2.mm, 2.mm)
                        #     fill_color 'fad31c'
                        #     fill
                        #     fill_color '222222'
                        #     text_box "<b>Stunde</b>", :at => [3.mm, h - 1.mm], :width => tw - 6.mm, :height => h - 2.mm, :align => :left, :valign => :center, :size => 18, :overflow => :shrink_to_fit, :inline_format => true
                        # end
                        %w(Montag Dienstag Mittwoch Donnerstag Freitag).each.with_index do |s, x|
                            bounding_box([tw + x * w, height], :width => w, :height => h) do
                                rounded_rectangle([0.5.mm, h - 0.5.mm], w - 1.mm, h - 1.mm, 2.mm)
                                fill_color palette[:primary_color_much_lighter][1, 6]
                                stroke_color palette[:primary][1, 6]
                                fill_and_stroke
                                # fill
                                fill_color '222222'
                                translate dx, dy do
                                    text_box "<b>#{s}</b>", :at => [3.mm, h - 1.mm], :width => w - 6.mm, :height => h - 2.mm, :align => :center, :valign => :center, :size => 18 * fscale, :overflow => :shrink_to_fit, :inline_format => true
                                end
                            end
                        end
                        (1..max_stunden).each do |y|
                            bounding_box([0.0, height - y * h], :width => tw, :height => h) do
                                # stroke_bounds
                                rounded_rectangle([0.5.mm, h - 0.5.mm], tw - 1.mm, h - 1.mm, 2.mm)
                                fill_color palette[:primary_color_much_lighter][1, 6]
                                stroke_color palette[:primary][1, 6]
                                fill_and_stroke
                                fill_color '222222'
                                text_box "<b>#{y}. Stunde</b>", :at => [1.mm, h - 1.mm], :width => tw - 2.mm, :height => h / 2, :align => :center, :valign => :bottom, :size => 16 * fscale, :overflow => :shrink_to_fit, :inline_format => true
                                text_box "#{hours[y][0]} – #{hours[y][1]}", :at => [1.mm, h / 2 - 1.mm], :width => tw - 2.mm, :height => h / 2 - 2.mm, :align => :center, :valign => :top, :size => 14 * fscale, :overflow => :shrink_to_fit
                            end
                            (0..4).each do |x|
                                info = (timetable[x] || {})[y]
                                if info
                                    bounding_box([tw + x * w, height - y * h], :width => w, :height => h) do
                                        # stroke_bounds
                                        transparent(0.5, 0.5) do
                                            rounded_rectangle([0.5.mm, h - 0.5.mm], w - 1.mm, h - 1.mm, 2.mm)
                                            fill_color palette[:primary_color_much_lighter][1, 6]
                                            stroke_color palette[:primary][1, 6]
                                            fill_and_stroke
                                        end
                                        fill_color '222222'
                                        faecher = []
                                        rooms = []
                                        info.each do |x|
                                            lesson_key = x[:lesson_key]
                                            fach = @@lessons[:lesson_keys][lesson_key][:fach]
                                            fach = @@faecher[fach] || fach
                                            fach.gsub!('Sport Jungen', 'Sport')
                                            fach.gsub!('Sport Mädchen', 'Sport')
                                            fach.gsub!('Evangelische Religionslehre', 'Religion')
                                            fach.gsub!('Katholische Religionslehre', 'Religion')
                                            fach.gsub!('Informationstechnischer Grundkurs', 'ITG')
                                            fach.gsub!('Politische Bildung', 'Politik')
                                            fach.gsub!('Gesellschaftswissenschaften', 'Gewi')
                                            fach.gsub!('Naturwissenschaften', 'Nawi')
                                            fach.gsub!('Streicher Anfänger', 'AGs')
                                            fach.gsub!('Basketball', 'AGs')
                                            fach.gsub!('Schach', 'AGs')
                                            fach.gsub!('Unterstufenorchester', 'AGs')
                                            fach.gsub!('AG Garten', 'AGs')
                                            fach.gsub!('BlblA', 'AGs')
                                            fach.gsub!('neugriechisch', 'ngr')
                                            fach.gsub!('(ngr)', '')
                                            fach.gsub!('Partnersprache', 'PS')
                                            fach.strip!
                                            faecher << fach
                                            rooms << x[:raum] unless fach == 'AGs'
                                        end
                                        translate dx, dy do
                                            text_box "<b>#{faecher.uniq.join("\n")}</b>", :at => [3.mm, h - 1.mm], :width => w - 13.mm, :height => h - 2.mm, :align => :left, :valign => :center, :size => 16 * fscale, :overflow => :shrink_to_fit, :inline_format => true
                                            text_box "#{rooms.join("\n")}", :at => [3.mm, h - 1.mm], :width => w - 6.mm, :height => h - 2.mm, :align => :right, :valign => :center, :size => 14 * fscale, :overflow => :shrink_to_fit, :inline_format => true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                image('/app/images/timetable1-front.png', :at => [0, 210.mm], :width => 297.mm, :height => 210.mm)
            end
        end
        return doc.render
    end

    def get_fehlzeiten_sheets_pdf(cache)
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
            font('RobotoCondensed') do
                move_down 1.cm
                text "Statistischer Erhebungsbogen der Fehlzeiten", :inline_format => true, :align => :center, :size => 14
                text "im <b>#{ZEUGNIS_HALBJAHR}. Schulhalbjahr #{ZEUGNIS_SCHULJAHR.gsub('_', '/')}</b>", :inline_format => true, :align => :center, :size => 14
                text "an öffentlichen allgemeinbildenen Schulen", :inline_format => true, :align => :center, :size => 14
                text "<b>06Y13 Gymnasium Steglitz</b>", :inline_format => true, :align => :center, :size => 14

                line_width 0.1.mm
                t = 35.mm
                l = 15.mm
                width = 297.mm - l * 2
                height = 210.mm - t - 1.cm
                count = ZEUGNIS_KLASSEN_ORDER.size + 2
                th = 20.mm
                tth= 6.mm
                w = width / 19
                h = (height - th) / count

                data = {}
                marked = Set.new()
                row56 = nil
                row710 = ZEUGNIS_KLASSEN_ORDER.size + 1
                ZEUGNIS_KLASSEN_ORDER.each.with_index do |klasse, i|
                    row56 ||= i if klasse.to_i >= 7
                end
                data["#{row56}/1"] = 0
                data["#{row710}/1"] = 0
                data["-1/3"] = 'keinen'
                data["-1/4"] = '1–4'
                data["-1/5"] = '5–7'
                data["-1/6"] = '8–10'
                data["-1/7"] = '11–20'
                data["-1/8"] = '21–40'
                data["-1/9"] = '>40'
                data["-1/10"] = 'keinen'
                data["-1/11"] = '1–4'
                data["-1/12"] = '5–7'
                data["-1/13"] = '8–10'
                data["-1/14"] = '11–20'
                data["-1/15"] = '21–40'
                data["-1/16"] = '>40'
                data["-1/17"] = "insge-\nsamt"
                data["-1/18"] = "darunter\nunent-\nschul-\ndigte"
                ZEUGNIS_KLASSEN_ORDER.each.with_index do |klasse, i|
                    # next unless klasse == '7c'
                    liste = @@zeugnisliste_for_klasse[klasse]
                    y = i
                    if klasse.to_i >= 7
                        y += 1
                    end
                    (0...19).each do |x|
                        key = "#{y}/#{x}"
                        v = nil
                        if x == 0
                            data[key] = "#{Main.tr_klasse(klasse)}"
                        elsif x == 1
                            v = liste[:schueler].size
                        elsif x == 2
                            v = 0
                            liste[:schueler].each do |sus|
                                email = sus[:email]
                                v += (cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fehltage:VSP/Email:#{email}"][0] || '0').to_i
                            end
                        elsif x == 17
                            v = 0
                            liste[:schueler].each do |sus|
                                email = sus[:email]
                                v += (cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fehltage:VT/Email:#{email}"][0] || '0').to_i
                            end
                        elsif x == 18
                            v = 0
                            liste[:schueler].each do |sus|
                                email = sus[:email]
                                v += (cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fehltage:VT_UE/Email:#{email}"][0] || '0').to_i
                            end
                        end
                        if v
                            data[key] = v
                            if klasse.to_i < 7
                                data["#{row56}/#{x}"] ||= 0
                                data["#{row56}/#{x}"] += v
                            else
                                data["#{row710}/#{x}"] ||= 0
                                data["#{row710}/#{x}"] += v
                            end
                        end
                    end
                    liste[:schueler].each do |sus|
                        email = sus[:email]
                        [['VT', 3], ['VT_UE', 10]].each do |pair|
                            v = (cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fehltage:#{pair[0]}/Email:#{email}"][0] || '0').to_i
                            x = 0
                            [0, 4, 7, 10, 20, 40, 10000000].each.with_index do |min, i|
                                if v > min
                                    x = i + 1
                                end
                            end
                            data["#{y}/#{x + pair[1]}"] ||= 0
                            data["#{y}/#{x + pair[1]}"] += 1
                            if klasse.to_i < 7
                                data["#{row56}/#{x + pair[1]}"] ||= 0
                                data["#{row56}/#{x + pair[1]}"] += 1
                            else
                                data["#{row710}/#{x + pair[1]}"] ||= 0
                                data["#{row710}/#{x + pair[1]}"] += 1
                            end
                        end
                    end
                end
                marked << row56
                marked << row710
                data["#{row56}/0"] = "5–6"
                data["#{row710}/0"] = "7–10"

                bounding_box([l, 210.mm - t], :width => width, :height => height) do
                    bounding_box([0 * w, height], :width => w, :height => th) do
                        text "Klasse", :align => :center, :valign => :center, :inline_format => true
                    end
                    bounding_box([1 * w, height], :width => w, :height => th) do
                        text "SuS\nins-\ngesamt", :align => :center, :valign => :center, :inline_format => true
                    end
                    bounding_box([2 * w, height], :width => w, :height => th) do
                        text "Verspä-\ntungen", :align => :center, :valign => :center, :inline_format => true
                    end
                    bounding_box([3 * w, height], :width => w * 7, :height => tth) do
                        text "Anzahl der SuS mit ____ Fehltagen", :align => :center, :valign => :center, :inline_format => true
                    end
                    bounding_box([10 * w, height], :width => w * 7, :height => tth) do
                        text "Anzahl der SuS mit unentschuldigten ____ Fehltagen", :align => :center, :valign => :center, :inline_format => true
                    end
                    bounding_box([17 * w, height], :width => w * 2, :height => tth) do
                        text "Fehltage", :align => :center, :valign => :center, :inline_format => true
                    end
                    (0...19).each do |x|
                        bounding_box([x * w, height - tth], :width => w, :height => th - tth) do
                            s = "#{data["-1/#{x}"]}"
                            text s, :align => :center, :valign => :center, :inline_format => true, :size => x == 18 ? 8 : 12
                        end
                    end
                    (0...(ZEUGNIS_KLASSEN_ORDER.size + 2)).each.with_index do |klasse, y|
                        (0...19).each do |x|
                            bounding_box([x * w, height - th - h * y], :width => w, :height => h) do
                                s = "#{data["#{y}/#{x}"]}".strip
                                s = '–' if s.empty?
                                if marked.include?(y)
                                    s = "<b>#{s}</b>"
                                    fill_color "eeeeee"
                                    rectangle [0, h], w, h
                                    fill
                                    fill_color "000000"
                                end
                                text s, :align => :center, :valign => :center, :inline_format => true
                            end
                        end
                    end
                    stroke_bounds
                    (0...count).each do |y|
                        line [0.0, height - th - y * h], [width, height - th - y * h]
                        stroke
                    end
                    (1...19).each do |x|
                        if [1, 2, 3, 10, 17].include?(x)
                            line [x * w, 0.0], [x * w, height]
                        else
                            line [x * w, 0.0], [x * w, height - tth]
                        end
                        stroke
                    end
                    line [3 * w, height - tth], [19 * w, height - tth]
                    stroke
                end

                puts ZEUGNIS_KLASSEN_ORDER.to_yaml
            end
        end
        return doc.render
    end

end

