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
end
