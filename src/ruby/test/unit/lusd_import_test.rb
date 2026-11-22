require_relative 'test_helper'
require 'tmpdir'
require_app 'lusd_import'

# LUSD export -> schueler/ASCII.TXT (src/scripts/lusd-to-ascii.rb).
# Made-up students only.
class LusdImportTest < Minitest::Test
    HEADER = ['Nachname', 'Vorname', 'Rufname', 'Klasse', 'Geschlecht', 'Geburtsdatum']
    ROWS = [
        ['Mustermann', 'Max', '', '05a', 'männlich', '01.01.2014'],
        ['Mustermann', 'Elisabeth Anna', 'Elli', '05a', 'weiblich', '02.01.2014'],
        ['Musterfrau', 'Erika', 'Erika', '5 B', 'w', '2014-03-04'],
        ['Beispiel', 'Paul Otto', '', 'Q1', 'm', '05.06.2008'],
    ]

    def with_file(content, name = 'export.csv')
        Dir.mktmpdir do |dir|
            path = File.join(dir, name)
            File.binwrite(path, content)
            yield path
        end
    end

    def csv(rows, sep: ';', encoding: 'UTF-8', bom: false)
        text = rows.map { |r| r.join(sep) }.join("\r\n") + "\r\n"
        text = "\uFEFF" + text if bom
        text.encode(encoding)
    end

    def convert(rows, map = {})
        LusdImport.convert(rows, map)
    end

    def test_writes_the_format_the_parser_reads
        result = convert([HEADER] + ROWS)
        assert_empty result[:errors]
        assert_equal [
            "Musterfrau\tErika\t5b\tw\t04.03.2014",
            "Mustermann\tElisabeth Anna\t5a\tw\t02.01.2014\tElli",
            "Mustermann\tMax\t5a\tm\t01.01.2014",
            "Beispiel\tPaul Otto\tq1\tm\t05.06.2008",
        ].sort, LusdImport.ascii_txt(result[:students]).lines.map(&:chomp).sort
    end

    def test_rufname_only_written_when_it_differs_from_the_first_vorname
        students = convert([HEADER] + ROWS)[:students]
        assert_nil students.find { |s| s.vorname == 'Erika' }.rufname
        assert_equal 'Elli', students.find { |s| s.vorname == 'Elisabeth Anna' }.rufname
        assert_equal 'Paul', students.find { |s| s.vorname == 'Paul Otto' }.effective_rufname
    end

    def test_reads_windows_1252_csv_with_semicolons
        with_file(csv([HEADER] + ROWS, encoding: 'Windows-1252')) do |path|
            rows = LusdImport.read_rows(path)
            assert_equal 'männlich', rows[1][4]
            assert_empty convert(rows)[:errors]
        end
    end

    def test_reads_utf8_csv_with_bom_tabs_and_title_rows
        rows = [['Schülerliste'], []] + [HEADER] + ROWS
        with_file(csv(rows, sep: "\t", bom: true)) do |path|
            result = convert(LusdImport.read_rows(path))
            assert_empty result[:errors]
            assert_equal 4, result[:students].size
            assert_equal 4, result[:students].first.row
        end
    end

    def test_reads_excel_with_date_cells
        require 'write_xlsx'
        Dir.mktmpdir do |dir|
            path = File.join(dir, 'export.xlsx')
            book = WriteXLSX.new(path)
            sheet = book.add_worksheet('Schüler')
            date = book.add_format(num_format: 'dd.mm.yyyy')
            sheet.write_row(0, 0, HEADER)
            ROWS.each_with_index do |r, i|
                sheet.write_row(i + 1, 0, r[0, 5])
                sheet.write_date_time(i + 1, 5, '2014-01-02T', date)
            end
            book.close
            result = convert(LusdImport.read_rows(path))
            assert_empty result[:errors]
            assert_equal ['02.01.2014'], result[:students].map(&:geburtsdatum).uniq
            assert_equal 'Elisabeth Anna', result[:students][1].vorname
        end
    rescue LoadError
        skip 'write_xlsx only in the container'
    end

    def test_class_names_are_normalised_and_mapped
        students = convert([HEADER] + ROWS, { 'Q1' => '12' })[:students]
        assert_equal ['5a', '5a', '5b', '12'], students.map(&:klasse)
        assert_equal 'q1', students.last.lusd_klasse
    end

    def test_rows_with_errors_name_no_one
        rows = [HEADER,
                ['Mustermann', 'Max', '', '5a', 'x', '01.01.2014'],
                ['Mustermann', 'Mia', '', '5a', 'w', '31.02.2014'],
                [''] * 6]
        errors = convert(rows)[:errors]
        assert_equal [2, 3], errors.map(&:first)
        assert_match(/Geschlecht »x« \(erlaubt: m, w, d\)/, errors[0][1])
        assert_match(/Geburtsdatum unlesbar/, errors[1][1])
        refute errors.flatten.join.include?('Mustermann')
    end

    # How the LUSD query assistant exports: one row per foreign language,
    # upper school without a class but with "Stufe/Semester", students who
    # left without either, and a placeholder in the name particle field.
    def test_lusd_query_export
        header = ['Schueler_Nachname', 'Schueler_Vorname', 'Schueler_Klassen_Klassenbezeichnung',
                  'Schueler_StufeSemester', 'Schueler_Geschlecht', 'Schueler_Geburtsdatum',
                  'Schueler_Namenszusatz', 'Schueler_Fremdsprache']
        rows = [header,
                ['Mustermann', 'Max', '05a', '05/1', 'm', '01.01.2014', 'Kein Zusatz da', 'Englisch'],
                ['Mustermann', 'Max', '05a', '05/1', 'm', '01.01.2014', 'Kein Zusatz da', 'Latein'],
                ['Oberstufe', 'Olga', '', '12/1', 'w', '02.02.2008', 'Kein Zusatz da', 'Englisch'],
                ['Hofe', 'Hans', '', '11/1', 'm', '03.03.2009', 'von', 'Englisch'],
                ['Gegangen', 'Gerd', '', '', 'm', '04.04.2009', 'Kein Zusatz da', 'Englisch']]
        result = convert(rows)
        assert_empty result[:errors]
        assert_equal 1, result[:duplicates]
        assert_equal 1, result[:skipped]
        assert_equal [['Mustermann', '5a'], ['Oberstufe', '12'], ['von Hofe', '11']],
                     result[:students].map { |s| [s.nachname, s.klasse] }
    end

    def test_bildungsgang_from_school_form_and_languages
        header = ['Schueler_Nachname', 'Schueler_Vorname', 'Schueler_Klassen_Klassenbezeichnung',
                  'Schueler_Geschlecht', 'Schueler_Geburtsdatum', 'Schueler_Schulform_kurz', 'Schueler_Fremdsprache']
        rows = [header]
        add = ->(name, form, *langs) { langs.each { |l| rows << [name, 'X', '7a', 'd', '01.01.2013', form, l] } }
        add.('Alt', 'GYM_AS_SEK_I', 'Englisch', 'Latein', 'Altgriechisch')
        add.('Sesb', 'SESB_SEK_I_GYM', 'Englisch', 'Neugriechisch', 'Französisch')
        add.('Lat', 'GYM_SEK_I', 'Englisch', 'Latein')
        add.('Frz', 'GYM_SEK_I', 'Englisch', 'Französisch')
        add.('Beide', 'GYM_SEK_I', 'Englisch', 'Französisch', 'Latein')
        add.('Willkommen', 'WKK', '')
        result = convert(rows)
        assert_empty result[:errors]
        assert_equal({ 'Alt' => 'altsprachlich', 'Sesb' => 'sesb', 'Lat' => 'regulaer_la', 'Frz' => 'regulaer_frz',
                       'Beide' => 'regulaer', 'Willkommen' => nil },
                     result[:students].to_h { |s| [s.nachname, s.bildungsgang] })
        assert_equal ['Englisch', 'Latein', 'Altgriechisch'].sort, result[:students].first.sprachen
        lines = LusdImport.ascii_txt(result[:students]).lines.map(&:chomp)
        assert_includes lines, "Alt\tX\t7a\td\t01.01.2013\t\taltsprachlich"
        assert_includes lines, "Willkommen\tX\t7a\td\t01.01.2013"
    end

    # all languages in one cell (Schueler_Fremdsprachen): their order decides
    def test_bildungsgang_from_ordered_languages
        header = ['Schueler_Nachname', 'Schueler_Vorname', 'Schueler_Klassen_Klassenbezeichnung', 'Schueler_Geschlecht',
                  'Schueler_Geburtsdatum', 'Schueler_Schulform_kurz', 'Schueler_Fremdsprachen', 'Schueler_Schluessel']
        rows = [header,
                ['La', 'X', '9a', 'w', '01.01.2011', 'GYM_SEK_I', 'Englisch, Latein, Französisch', '4711'],
                ['Frz', 'X', '9a', 'm', '02.01.2011', 'GYM_SEK_I', 'Englisch, Französisch, Latein', '4712']]
        result = convert(rows)
        assert_equal({ 'La' => 'regulaer_la', 'Frz' => 'regulaer_frz' }, result[:students].to_h { |s| [s.nachname, s.bildungsgang] })
        assert_equal ['4711', '4712'], result[:students].map(&:lusd_id)
    end

    # headings as the LUSD query assistant writes them
    def test_lusd_field_names
        header = ['Ansprechpartner1_Nachname', 'Schüler_Nachname', 'Schüler_Vorname', 'Schüler_Rufname',
                  'Klassen_Klassenbezeichnung', 'Klassen_Stufe', 'Schüler_Geschlecht', 'Schüler_Geburtsdatum']
        row = ['Elternteil', 'Mustermann', 'Max', '', '05a', '5', 'm', '01.01.2014']
        result = convert([header, row])
        assert_empty result[:errors]
        s = result[:students].first
        assert_equal ['Mustermann', 'Max', '5a', 'm', '01.01.2014'],
                     [s.nachname, s.vorname, s.klasse, s.geschlecht, s.geburtsdatum]
    end

    def test_missing_columns_are_named
        e = assert_raises(LusdImport::Error) { convert([['Nachname', 'Vorname', 'Klasse'], ['A', 'B', '5a']]) }
        assert_match(/Geschlecht, Geburtsdatum/, e.message)
        e = assert_raises(LusdImport::Error) { convert([['Foo', 'Bar']]) }
        assert_match(/Keine Kopfzeile/, e.message)
    end

    def test_report_compares_with_the_current_file
        current = [
            "Mustermann\tMax\t5a\tm\t01.01.2014",
            "Mustermann\tElisabeth\t5a\tw\t02.01.2014\tElli",
            "Musterfrau\tErika\t5b\tw\t04.03.2014",
            "Beispiel\tPaul\t12\tm\t05.06.2008",
            "Beispiel\tPetra\t12\tw\t06.07.2008",
            "# Kommentar",
        ].join("\n")
        rows = [HEADER] + ROWS.map(&:dup)
        rows[4][0] = 'Beispiel-Neu' # Nachname changed: new e-mail address
        with_file(current, 'ASCII.TXT') do |path|
            old = LusdImport.read_current(path)
            report = LusdImport.report(convert(rows), old_students: old)
            assert_match(/^12\s+2\s+0\s+-2  fehlt im Export$/, report)
            assert_match(/^q1\s+0\s+1\s+\+1  neue Klasse$/, report)
            assert_match(/nur auf, wenn sie in KLASSEN_ORDER stehen/, report)
            assert_match(/Zugeordnet: 4, nur im Export: 0, nur in der bisherigen Datei: 1/, report)
            assert_match(/q1 im Export: 1 bisher in 12/, report)
            assert_match(/Vorschlag \(bei gleichem Schuljahr\): --klasse q1=12/, report)
            assert_match(/neue E-Mail-Adresse\): 1$/, report)
            assert_match(/Nur weitere Vornamen anders geschrieben: 1$/, report)
            refute_match(/Beispiel|Mustermann|Erika/, report)
            named = LusdImport.report(convert(rows), old_students: old, show_names: true)
            assert_match(/Zeile 5: Paul Beispiel -> Paul Beispiel-Neu/, named)
        end
    end

    def test_example_data_round_trips
        path = in_test_stack? ? '/data/schueler/ASCII.TXT' :
            File.join(APP_ROOT, '..', 'example-data', 'schueler', 'ASCII.TXT')
        skip 'example data not mounted' unless File.exist?(path)
        old = LusdImport.read_current(path)
        rows = [HEADER] + old.map do |s|
            [s.nachname, s.vorname, s.rufname.to_s, s.klasse,
             s.geschlecht, s.geburtsdatum.to_s]
        end
        result = convert(rows)
        assert_empty result[:errors]
        report = LusdImport.report(result, old_students: old)
        assert_match(/neue E-Mail-Adresse\): 0$/, report)
    end

    # /datenpflege names the columns found and the missing ones; a tutor
    # column is recognised (for 11/12)
    def test_column_report
        rows = [['Schueler_Nachname', 'Schueler_Vorname', 'Klasse', 'Geschlecht', 'Tutor']]
        report = LusdImport.column_report(rows).to_h { |x| [x[:field], x] }
        assert_equal 'Schueler_Nachname', report[:nachname][:found]
        assert_equal 'Tutor', report[:tutor][:found]
        assert_nil report[:geburtsdatum][:found]
        assert report[:geburtsdatum][:required]
        refute report[:rufname][:required]
        assert_nil LusdImport.column_report([['Name', 'Ort']])
    end

    # Latin and French: the Sprachenfolge decides the Bildungsgang – a number
    # per language row, or the languages in order in one cell
    def test_sprachenfolge
        header = ['Nachname', 'Vorname', 'Klasse', 'Geschlecht', 'Geburtsdatum', 'Schulform_kurz', 'Fremdsprache', 'Sprachenfolge']
        rows = [header,
            ['Muster', 'Ina', '7a', 'w', '01.01.2013', 'GYM', 'Englisch', '1'],
            ['Muster', 'Ina', '7a', 'w', '01.01.2013', 'GYM', 'Französisch', '2'],
            ['Muster', 'Ina', '7a', 'w', '01.01.2013', 'GYM', 'Latein', '3'],
            ['Probe', 'Jan', '7a', 'm', '02.02.2013', 'GYM', 'Latein', '2. Fremdsprache'],
            ['Probe', 'Jan', '7a', 'm', '02.02.2013', 'GYM', 'Französisch', '3. Fremdsprache'],
            ['Probe', 'Jan', '7a', 'm', '02.02.2013', 'GYM', 'Englisch', '1. Fremdsprache'],
            ['Liste', 'Kim', '7a', 'd', '03.03.2013', 'GYM', 'Latein', 'E, F, L'],
            ['Liste', 'Kim', '7a', 'd', '03.03.2013', 'GYM', 'Französisch', 'E, F, L'],
            ['Ohne', 'Ole', '7a', 'm', '04.04.2013', 'GYM', 'Latein', ''],
            ['Ohne', 'Ole', '7a', 'm', '04.04.2013', 'GYM', 'Französisch', '']]
        by = LusdImport.convert(rows)[:students].to_h { |st| [st.vorname, st] }
        assert_equal 'regulaer_frz', by['Ina'].bildungsgang
        assert_equal ['Englisch', 'Französisch', 'Latein'], by['Ina'].sprachen
        assert_equal 'regulaer_la', by['Jan'].bildungsgang
        assert_equal 'regulaer_frz', by['Kim'].bildungsgang
        # without an order: just regular, as before
        assert_equal 'regulaer', by['Ole'].bildungsgang
        assert LusdImport.column_report(rows).find { |x| x[:field] == :sprachenfolge }[:found]
    end
end
