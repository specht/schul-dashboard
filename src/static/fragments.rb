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
                                    text "<b>VERTRAULICH</b>", :align => :center, :inline_format => true, :size => 24, :valign => :center
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
                                        text "<b>Nr.</b>", :align => :right, :inline_format => true, :size => 12
                                    end
                                    bounding_box([nr_width + 2.mm, row_height * (n_per_page + 1)], width: name_width - 2.mm, height: row_height) do
                                        move_down row_height * 0.5 - 6
                                        text "<b>Name</b>", :align => :left, :inline_format => true, :size => 12
                                    end
                                    (0...liste[:faecher].size).each do |x|
                                        bounding_box([(nr_width + name_width) + fach_width * x, row_height * (n_per_page + 1)], width: fach_width, height: row_height) do
                                            move_down row_height * 0.5 - 6
                                            fach = liste[:faecher][x]
                                            text "<b>#{fach}</b>#{FAECHER_SPRACHEN.include?(fach) ? '<sup>1</sup>' : ''}", :align => :center, :inline_format => true, :size => 12
                                            # stroke_bounds
                                        end
                                    end
                                    (0...n).each do |i|
                                        j = i + offset
                                        email = consider_sus_for_klasse[klasse][j]
                                        bounding_box([0.mm, row_height * (n_per_page - i)], width: nr_width - 1.mm, height: row_height) do
                                            move_down row_height * 0.5 - 12
                                            text "#{i + offset + 1}.", :align => :right, :inline_format => true, :size => 12
                                            # stroke_bounds
                                        end
                                        bounding_box([nr_width + 2.mm, row_height * (n_per_page - i)], width: name_width - 2.mm, height: row_height) do
                                            move_down row_height * 0.5 - 12
                                            s = "#{@@user_info[email][:last_name]}"
                                            text elide_string(s, name_width - 2.mm, {:size => 12}), :align => :left, :inline_format => true, :size => 12
                                            save_graphics_state do
                                                translate 2.mm, 0.mm
                                                s = "#{@@user_info[email][:official_first_name]}"
                                                text elide_string(s, name_width - 2.mm - 2.mm, {:size => 12}), :align => :left, :inline_format => true, :size => 12
                                            end
                                            # stroke_bounds
                                        end
                                        (0...liste[:faecher].size).each do |x|
                                            fach = liste[:faecher][x]
                                            bounding_box([(nr_width + name_width) + fach_width * x, row_height * (n_per_page - i)], width: fach_width, height: row_height) do
                                                if FAECHER_SPRACHEN.include?(fach)
                                                    bounding_box([0.mm, row_height], width: fach_width / 2, height: row_height / 2) do
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}_AT/Email:#{email}"]
                                                        if note
                                                            float do
                                                                text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :size => 12, :final_gap => false, :valign => :center
                                                                if NOTEN_MARK.include?(note)
                                                                    save_graphics_state do
                                                                        translate(fach_width / 4, row_height / 4)
                                                                        stroke_circle [0, 0], 12
                                                                    end
                                                                end
                                                            end
                                                        end
                                                        stroke_bounds
                                                    end
                                                    bounding_box([0.mm, row_height / 2], width: fach_width / 2, height: row_height / 2) do
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}_SL/Email:#{email}"]
                                                        if note
                                                            float do
                                                                text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :size => 12, :final_gap => false, :valign => :center
                                                                if NOTEN_MARK.include?(note)
                                                                    save_graphics_state do
                                                                        translate(fach_width / 4, row_height / 4)
                                                                        stroke_circle [0, 0], 12
                                                                    end
                                                                end
                                                            end
                                                        end
                                                        stroke_bounds
                                                    end
                                                    bounding_box([fach_width / 2, row_height], width: fach_width / 2, height: row_height) do
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"]
                                                        if note
                                                            float do
                                                                text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :size => 12, :final_gap => false, :valign => :center
                                                                if NOTEN_MARK.include?(note)
                                                                    save_graphics_state do
                                                                        translate(fach_width / 4, row_height / 2)
                                                                        stroke_circle [0, 0], 12
                                                                    end
                                                                end
                                                            end
                                                        end
                                                    end
                                                else
                                                    note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"]
                                                    if note
                                                        text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :inline_format => true, :size => 12, :valign => :center
                                                        if NOTEN_MARK.include?(note)
                                                            save_graphics_state do
                                                                translate(fach_width / 2, row_height / 2)
                                                                stroke_circle [0, 0], 12
                                                            end
                                                        end
                                                    end
                                                end
                                                # stroke_bounds
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
end
