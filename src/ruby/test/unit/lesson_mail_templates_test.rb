require_relative 'test_helper'
require_app 'lesson_mail_templates'
require 'json'

class LessonMailTemplatesTest < Minitest::Test
    def vars(geschlecht: 'm', note: '')
        {:first_name => 'Max', :name => 'Max Mustermann', :klasse => '5a', :fach => 'Mathematik',
         :note => note, :teacher => 'Frau Lehrerin', :lesson_teacher => 'Herr Clarke', :geschlecht => geschlecht}
    end

    def normalize(html)
        html.gsub(/\s+/, ' ').gsub(/\s*(<[^>]+>)\s*/, '\1').strip
    end

    # The default texts are the ones the mail bot had built in before they
    # became editable (lesson_mail_templates_golden.json was produced by the
    # old code). The Otium mail is the exception: it is now signed by the
    # teacher on Otium duty who sends it and names the lesson's teacher.
    def test_defaults_reproduce_the_former_mails
        golden = JSON.parse(File.read(File.join(__dir__, 'lesson_mail_templates_golden.json')))
        assert_equal 21, golden.size
        golden.each do |key, (subject, html)|
            reason, geschlecht, note = key.split('/', 3)
            next if reason == 'disturbance_otium'
            rendered = LessonMailTemplates.render(LessonMailTemplates::DEFAULTS[reason], vars(geschlecht: geschlecht, note: note))
            assert_equal subject, rendered[:subject], key
            assert_equal normalize(html), normalize(rendered[:html]), key
        end
    end

    def test_otium_mail_names_the_lesson_teacher
        rendered = LessonMailTemplates.render(LessonMailTemplates::DEFAULTS['disturbance_otium'], vars(geschlecht: 'w', note: 'Lärm'))
        assert_equal 'Störverhalten (Otium)', rendered[:subject]
        assert_includes rendered[:html], 'Ihre Tochter Max zeigte heute im Fach Mathematik ein derart ausgeprägtes Störverhalten (Lärm), dass Herr Clarke sie im Sinne ihrer Mitschüler:innen'
        assert_includes rendered[:html], 'nacharbeiten. Bitte sprechen Sie eingehend mit Max über die Konsequenzen ihres Verhaltens.'
        assert_includes rendered[:html], "Mit freundlichen Grüßen<br>\nFrau Lehrerin</p>"
    end

    def test_every_reason_has_a_valid_default
        assert_equal LessonMailTemplates::REASONS.sort, LessonMailTemplates::DEFAULTS.keys.sort
        assert_equal LessonMailTemplates::REASONS.sort, LessonMailTemplates::LABELS.keys.sort
        LessonMailTemplates::DEFAULTS.each do |reason, template|
            assert_empty LessonMailTemplates.template_errors(template[:subject], template[:body]), reason
        end
    end

    def test_placeholders_gender_and_paragraphs
        template = {:subject => '{Name} ({Klasse}) – {Fach}', :body => "Hallo,\n\n{Er|Sie} war da{notiz}.\nGruß\n\n\n{ Lehrkraft }"}
        boy = LessonMailTemplates.render(template, vars(note: "Zirkel\nfehlt "))
        assert_equal 'Max Mustermann (5a) – Mathematik', boy[:subject]
        assert_equal "<p>Hallo,</p>\n<p>Er war da (Zirkel fehlt).<br>\nGruß</p>\n<p>Frau Lehrerin</p>\n", boy[:html]
        girl = LessonMailTemplates.render(template, vars(geschlecht: 'w'))
        assert_includes girl[:html], 'Sie war da.<br>'
        # anything but 'm' gets the second text, as before
        assert_includes LessonMailTemplates.render(template, vars(geschlecht: nil))[:html], 'Sie war da.'
    end

    # divers: a third form if the text has one, else both
    def test_divers
        both = {:subject => 'x', :body => '{Er|Sie} war da.'}
        assert_includes LessonMailTemplates.render(both, vars(geschlecht: 'd'))[:html], 'Er/Sie war da.'
        three = {:subject => 'x', :body => '{Er|Sie|Max} war da.'}
        assert_includes LessonMailTemplates.render(three, vars(geschlecht: 'd'))[:html], 'Max war da.'
        assert_includes LessonMailTemplates.render(three, vars(geschlecht: 'w'))[:html], 'Sie war da.'
    end

    def test_texts_and_values_are_escaped
        template = {:subject => 'A & B {Vorname}', :body => '<b>{Vorname}</b>{Notiz}'}
        rendered = LessonMailTemplates.render(template, vars(note: '<script>x</script>').merge(:first_name => 'M&M'))
        assert_equal 'A & B M&M', rendered[:subject]
        assert_equal "<p>&lt;b&gt;M&amp;M&lt;/b&gt; (&lt;script&gt;x&lt;/script&gt;)</p>\n", rendered[:html]
    end

    def test_errors
        assert_empty LessonMailTemplates.template_errors('Lob für {vorname}', 'Text {Ihr Sohn|Ihre Tochter} {lehrkraft  der Stunde}')
        assert_equal ['Betreff ist leer.'], LessonMailTemplates.template_errors('  ', 'Text')
        assert_equal ['Text: Den Platzhalter {Vornam} gibt es nicht.'], LessonMailTemplates.template_errors('X', 'Hallo {Vornam}')
        assert_match(/genau zwei Texte/, LessonMailTemplates.template_errors('X', '{a|b|c}').first)
        assert_match(/nicht geschlossen/, LessonMailTemplates.template_errors('X', 'Hallo {Vorname').first)
        assert_match(/nicht geschlossen/, LessonMailTemplates.template_errors('X}', 'Hallo').first)
        assert_match(/zu lang/, LessonMailTemplates.template_errors('X', 'a' * 5001).first)
    end

    def test_effective_falls_back_to_default
        stored = {'praise' => {:subject => 'Super', :body => 'Toll'}, 'late' => {:subject => '', :body => 'x'}}
        assert_equal({:subject => 'Super', :body => 'Toll'}, LessonMailTemplates.effective(stored, 'praise'))
        assert_equal LessonMailTemplates::DEFAULTS['late'], LessonMailTemplates.effective(stored, 'late')
        assert_equal LessonMailTemplates::DEFAULTS['homework'], LessonMailTemplates.effective(nil, 'homework')
    end

    # ---- own templates ----

    def stored_with_own
        {
            'praise' => {:subject => 'Super', :body => 'Toll', :custom => false},
            'eigen_b2c3d4f5' => {:subject => 'Sport', :body => 'Text', :custom => true, :label => 'Sportzeug fehlt',
                                 :color => '#204a87', :status => 'active', :ts_created => 200},
            'eigen_a1b2c3d4' => {:subject => 'Probe', :body => 'Text', :custom => true, :label => 'Neu im Test',
                                 :color => 'kaputt', :status => 'test', :ts_created => 100},
            'eigen_zzzz9999' => {:subject => 'Alt', :body => 'Text', :custom => true, :label => 'Alt',
                                 :color => '#ffffff', :status => 'hidden', :ts_created => 300},
            # not an own template: wrong prefix
            'fremd' => {:subject => 'x', :body => 'y', :custom => true, :label => 'Fremd', :status => 'active'},
        }
    end

    def test_catalog_lists_built_in_then_own_by_age
        catalog = LessonMailTemplates.catalog(stored_with_own)
        assert_equal LessonMailTemplates::REASONS + %w(eigen_a1b2c3d4 eigen_b2c3d4f5 eigen_zzzz9999), catalog.map { |x| x[:reason] }
        assert catalog.first(7).all? { |x| x[:status] == 'active' && !x[:custom] }
        own = catalog.find { |x| x[:reason] == 'eigen_a1b2c3d4' }
        assert_equal 'Neu im Test', own[:label]
        assert_equal 'test', own[:status]
        # an invalid colour falls back
        assert_equal LessonMailTemplates::DEFAULT_CUSTOM_COLOR, own[:color]
        assert_equal '#ffffff', LessonMailTemplates.find(stored_with_own, 'eigen_b2c3d4f5')[:text_color]
        assert_equal '#000000', LessonMailTemplates.find(stored_with_own, 'eigen_zzzz9999')[:text_color]
        assert_nil LessonMailTemplates.find(stored_with_own, 'fremd')
        assert_equal 7, LessonMailTemplates.catalog(nil).size
    end

    def test_from_nodes
        stored = LessonMailTemplates.from_nodes([
            {:reason => 'eigen_a1b2c3d4', :custom => true, :label => 'X', :status => 'komisch', :subject => 's', :body => 'b'},
            {:reason => 'late', :subject => 's', :body => 'b'},
        ])
        assert_equal false, stored['late'][:custom]
        # an unknown state counts as a test
        assert_equal 'test', LessonMailTemplates.find(stored, 'eigen_a1b2c3d4')[:status]
    end

    def test_who_may_send_with_which_template
        stored = stored_with_own
        active = LessonMailTemplates.find(stored, 'eigen_b2c3d4f5')
        test = LessonMailTemplates.find(stored, 'eigen_a1b2c3d4')
        hidden = LessonMailTemplates.find(stored, 'eigen_zzzz9999')
        assert LessonMailTemplates.sendable?(LessonMailTemplates.find(stored, 'praise'), false)
        assert LessonMailTemplates.sendable?(active, false)
        refute LessonMailTemplates.sendable?(test, false)
        assert LessonMailTemplates.sendable?(test, true)
        refute LessonMailTemplates.sendable?(hidden, true)
        refute LessonMailTemplates.sendable?(LessonMailTemplates.find(stored, 'unbekannt'), true)
        # the Otium mail only the Otium
        otium = LessonMailTemplates.find(stored, 'disturbance_otium')
        refute LessonMailTemplates.sendable?(otium, true)
        assert LessonMailTemplates.sendable?(otium, false, true)
    end

    # the rules of the built-in reasons, as before they came into the database
    def test_builtin_rules
        catalog = LessonMailTemplates.catalog({})
        otium = catalog.find { |x| x[:reason] == 'disturbance_otium' }
        assert_equal 'otium', otium[:sender]
        assert otium[:cc_klassenleitung]
        (catalog - [otium]).each do |x|
            assert_equal 'teachers', x[:sender], x[:reason]
            refute x[:cc_klassenleitung], x[:reason]
        end
        assert_equal 'Zirkel fehlt', catalog.find { |x| x[:reason] == 'material' }[:note_hint]
        assert_equal '', catalog.find { |x| x[:reason] == 'praise' }[:note_hint]
        assert_equal '#4aa03f', catalog.find { |x| x[:reason] == 'praise' }[:color]
    end

    # what is stored wins; a built-in reason is never a test
    def test_stored_rules_win
        stored = {
            'late' => {:label => 'Zu spät', :color => '#000000', :status => 'hidden', :sender => 'otium',
                       :cc_klassenleitung => true, :note_hint => ''},
            'praise' => {:status => 'test', :cc_klassenleitung => false},
            'disturbance_otium' => {:cc_klassenleitung => false},
        }
        late = LessonMailTemplates.find(stored, 'late')
        assert_equal ['Zu spät', '#000000', '#ffffff', 'hidden', 'otium', true, ''],
                     late.values_at(:label, :color, :text_color, :status, :sender, :cc_klassenleitung, :note_hint)
        assert_equal 'active', LessonMailTemplates.find(stored, 'praise')[:status]
        refute LessonMailTemplates.find(stored, 'disturbance_otium')[:cc_klassenleitung]
        # an own template starts with the plain rules
        own = LessonMailTemplates.find({'eigen_a1b2c3d4' => {:custom => true, :label => 'X'}}, 'eigen_a1b2c3d4')
        assert_equal ['test', 'teachers', false, ''], own.values_at(:status, :sender, :cc_klassenleitung, :note_hint)
    end

    def test_rule_errors
        good = {:label => 'Turnbeutel', :color => '#204a87', :status => 'active', :sender => 'teachers',
                :cc_klassenleitung => false, :note_hint => 'Sport'}
        assert_empty LessonMailTemplates.rule_errors(good, {}, nil, true)
        assert_empty LessonMailTemplates.rule_errors(good.merge(:label => 'Verspätung'), {}, 'late', false)
        assert_match(/Zustand/, LessonMailTemplates.rule_errors(good.merge(:status => 'test'), {}, 'late', false).first)
        assert_empty LessonMailTemplates.rule_errors(good.merge(:status => 'test'), {}, nil, true)
        assert_match(/Farbe/, LessonMailTemplates.rule_errors(good.merge(:color => 'red'), {}, nil, true).first)
        assert_match(/schickt/, LessonMailTemplates.rule_errors(good.merge(:sender => 'alle'), {}, nil, true).first)
        assert_match(/Klassenleitung/, LessonMailTemplates.rule_errors(good.merge(:cc_klassenleitung => 'ja'), {}, nil, true).first)
        assert_match(/zu lang/, LessonMailTemplates.rule_errors(good.merge(:note_hint => 'x' * 61), {}, nil, true).first)
    end

    def test_own_templates_have_no_default
        assert_equal({:subject => 'Sport', :body => 'Text'}, LessonMailTemplates.effective(stored_with_own, 'eigen_b2c3d4f5'))
        assert_nil LessonMailTemplates.effective({}, 'eigen_b2c3d4f5')
        assert LessonMailTemplates.custom_reason?('eigen_b2c3d4f5')
        refute LessonMailTemplates.custom_reason?('praise')
        refute LessonMailTemplates.custom_reason?('eigen_')
        refute LessonMailTemplates.custom_reason?("eigen_abcd\n")
    end

    def test_label_errors
        stored = stored_with_own
        assert_empty LessonMailTemplates.label_errors('Turnbeutel vergessen', stored)
        assert_equal ['Der Name ist leer.'], LessonMailTemplates.label_errors('  ', stored)
        assert_match(/zu lang/, LessonMailTemplates.label_errors('a' * 61, stored).first)
        # names are unique, also against the built-in ones
        assert_match(/gibt es schon/, LessonMailTemplates.label_errors('sportzeug fehlt', stored).first)
        assert_match(/gibt es schon/, LessonMailTemplates.label_errors('Verspätung', stored).first)
        # an own template keeps its name
        assert_empty LessonMailTemplates.label_errors('Sportzeug fehlt', stored, 'eigen_b2c3d4f5')
    end

    # A test mail goes to the sender alone, without the archive copy; a real
    # one as before.
    def test_envelope
        normal = LessonMailTemplates.envelope(test: false, sender: 'lehrer@s.de', student: 'kind@s.de',
                                              lesson_teacher: 'clarke@s.de', klassenleitung: ['kl@s.de', 'lehrer@s.de'])
        assert_equal ['eltern.kind@s.de'], normal[:to]
        assert_equal ['kind@s.de', 'lehrer@s.de', 'clarke@s.de', 'kl@s.de'], normal[:cc]
        assert normal[:archive]
        own_lesson = LessonMailTemplates.envelope(test: false, sender: 'clarke@s.de', student: 'kind@s.de', lesson_teacher: 'clarke@s.de')
        assert_equal ['kind@s.de', 'clarke@s.de'], own_lesson[:cc]
        test = LessonMailTemplates.envelope(test: true, sender: 'lehrer@s.de', student: 'kind@s.de',
                                            lesson_teacher: 'clarke@s.de', klassenleitung: ['kl@s.de'])
        assert_equal({:to => ['lehrer@s.de'], :cc => [], :archive => false}, test)
    end

    def test_mark_as_test
        rendered = LessonMailTemplates.render({:subject => 'Sport {Vorname}', :body => 'Hallo'}, vars)
        marked = LessonMailTemplates.mark_as_test(rendered, 'Sport <b>', 'Max Mustermann (5a)')
        assert_equal '[TEST] Sport Max', marked[:subject]
        assert_includes marked[:html], 'Testmail der Vorlage »Sport &lt;b&gt;«'
        assert_includes marked[:html], 'an die Eltern von Max Mustermann (5a)'
        assert marked[:html].end_with?("<p>Hallo</p>\n")
    end

    # the built-in texts are in the database; »changed« compares with the default
    def test_default_text
        default = LessonMailTemplates::DEFAULTS['late']
        assert LessonMailTemplates.default_text?('late', default[:subject], default[:body])
        assert LessonMailTemplates.default_text?('late', " #{default[:subject]} ", default[:body].strip.gsub("\n", "\r\n"))
        refute LessonMailTemplates.default_text?('late', default[:subject], 'anders')
        refute LessonMailTemplates.default_text?('eigen_a1b2c3d4', 'x', 'y')
    end

    # the note is the same for all picked students, the comment is per student;
    # {Notiz} holds both
    def test_note_and_comment
        template = {:subject => 'x', :body => 'Max war unruhig{Notiz}.'}
        both = LessonMailTemplates.render(template, vars(note: 'Sitzplan', geschlecht: 'm').merge(:comment => " hat sich\numgesetzt "))
        assert_includes both[:html], 'Max war unruhig (Sitzplan; hat sich umgesetzt).'
        only_comment = LessonMailTemplates.render(template, vars.merge(:comment => 'vor der Tür'))
        assert_includes only_comment[:html], 'Max war unruhig (vor der Tür).'
        assert_includes LessonMailTemplates.render(template, vars(note: 'Sitzplan'))[:html], 'unruhig (Sitzplan).'
        assert_includes LessonMailTemplates.render(template, vars.merge(:comment => '  '))[:html], 'Max war unruhig.'
    end

    # a text the teacher changed for one student is taken as it is: escaped,
    # paragraphs as usual, braces are no placeholders; the subject stays
    def test_changed_text
        template = {:subject => 'Lob für {Vorname}', :body => 'Hallo {Vorname}'}
        normal = LessonMailTemplates.render(template, vars)
        assert_equal 'Hallo Max', normal[:text]
        changed = LessonMailTemplates.render(template, vars, "Liebe Eltern,\r\n\r\n{Vorname} <b>war</b> toll.\nGruß")
        assert_equal 'Lob für Max', changed[:subject]
        assert_equal "<p>Liebe Eltern,</p>\n<p>{Vorname} &lt;b&gt;war&lt;/b&gt; toll.<br>\nGruß</p>\n", changed[:html]
        assert_equal normal[:html], LessonMailTemplates.render(template, vars, '  ')[:html]
    end

    # {Datum}: the lesson's day – »heute« when the mail goes out that day,
    # the weekday and date when a teacher sends it later
    def test_date_placeholder
        today = Date.new(2026, 11, 25)
        assert_equal 'heute', LessonMailTemplates.date_phrase('2026-11-25', today)
        assert_equal 'am Montag, 23.11.', LessonMailTemplates.date_phrase('2026-11-23', today)
        assert_equal 'heute', LessonMailTemplates.date_phrase(nil, today)
        assert_equal 'heute', LessonMailTemplates.date_phrase('kaputt', today)
        template = {:subject => 'x', :body => '{Vorname} hat {Datum} gefehlt.'}
        later = LessonMailTemplates.render(template, vars.merge(:datum => '2026-11-23', :today => today))
        assert_includes later[:html], 'Max hat am Montag, 23.11. gefehlt.'
        assert_empty LessonMailTemplates.template_errors('x', 'Am {Datum}')
    end

    # The defaults say {Datum} now; on the lesson's day the mail reads as
    # before (»heute«), the old texts are known for the switch at startup.
    def test_defaults_with_date
        LessonMailTemplates::REASONS.each do |reason|
            body = LessonMailTemplates::DEFAULTS[reason][:body]
            assert_includes body, '{Datum}', reason
            legacy = LessonMailTemplates::LEGACY_DEFAULT_BODIES[reason]
            assert_includes legacy, 'heute', reason
            refute_includes legacy, '{Datum}', reason
            today = LessonMailTemplates.render({:subject => 'x', :body => body}, vars.merge(:datum => Date.today.to_s))
            old = LessonMailTemplates.render({:subject => 'x', :body => legacy}, vars)
            assert_equal old[:html], today[:html], reason
        end
    end

    def test_new_template_body_is_valid
        assert_empty LessonMailTemplates.template_errors('Betreff', LessonMailTemplates::NEW_TEMPLATE_BODY)
    end
end
