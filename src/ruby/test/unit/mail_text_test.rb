require_relative 'test_helper'
require_app 'mail_text'

class MailTextTest < Minitest::Test
    def test_plain_text_keeps_paragraphs_and_line_breaks
        assert_equal "Hallo,\n\n\nText\nGruß", MailText.html_to_plain_text("<p>Hallo,</p>\n<p>Text<br>Gruß</p>\n")
    end

    # escaped values (e.g. a teacher's note in a lesson mail) read normally
    def test_entities_become_characters
        assert_equal 'Lineal & Zirkel <fehlen> "heute"', MailText.html_to_plain_text('<p>Lineal &amp; Zirkel &lt;fehlen&gt; &quot;heute&quot;</p>')
    end
end
