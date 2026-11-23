require_relative 'test_helper'

# Comparing an uploaded student list with the current one (/datenpflege,
# include/datenpflege.rb): who is new, gone, in another class – and who would
# get a new address (and so a new account) because the name is spelled
# differently. Made-up students; classes from the example data.
class DatenpflegeDiffTest < Minitest::Test
    def setup
        skip 'needs the test stack (./test.sh unit)' unless in_test_stack?
        Dir.chdir(APP_ROOT) do
            require_app 'parser'
            require_app 'include/datenpflege'
        end
        I18n.enforce_available_locales = false
        @main = Main.allocate
        # main.rb isn't loaded in the unit tests
        Main.define_singleton_method(:tr_bildungsgang) { |x| x.to_s } unless Main.respond_to?(:tr_bildungsgang)
    end

    def student(email, first, last, klasse, geburtstag = '2014-01-01')
        { :email => email, :first_name => first, :official_first_name => first, :last_name => last,
          :display_name => "#{first} #{last}", :klasse => klasse, :geburtstag => geburtstag }
    end

    def test_diff
        old = [
            student('max.mustermann@x', 'Max', 'Mustermann', '5a', '2014-01-01'),
            student('mia.mustermann@x', 'Mia', 'Mustermann', '5a', '2014-02-02'),
            student('paul.beispiel@x', 'Paul', 'Beispiel', '5b', '2014-03-03'),
            student('emil.weg@x', 'Emil', 'Weg', '5c', '2014-04-04'),
        ]
        new = [
            student('max.mustermann@x', 'Max', 'Mustermann', '5a', '2014-01-01'),
            student('mia.mustermann@x', 'Mia', 'Mustermann', '5b', '2014-02-02'),
            # same person, double-barrelled name now: another address
            student('paul.beispiel-neu@x', 'Paul', 'Beispiel-Neu', '5b', '2014-03-03'),
            student('nina.neu@x', 'Nina', 'Neu', '5c', '2014-05-05'),
            student('quentin.q@x', 'Quentin', 'Q', 'q9', '2008-01-01'),
        ]
        d = @main.datenpflege_diff(old, new)
        assert_equal 4, d[:old_total]
        assert_equal 4, d[:new_total], 'q9 is not a class of the dashboard'
        assert_equal ['nina.neu@x'], d[:added].map { |r| r[:email] }
        assert_equal ['emil.weg@x'], d[:removed].map { |r| r[:email] }
        assert_equal [['paul.beispiel@x', 'paul.beispiel-neu@x']], d[:moved].map { |o, n| [o[:email], n[:email]] }
        assert_equal [['mia.mustermann@x', [['Klasse', '5a', '5b']]]], d[:changed].map { |o, n, ch| [n[:email], ch] }
        assert_equal ['quentin.q@x'], d[:dropped].map { |r| r[:email] }
    end

    # every kind of change, in one entry per student
    def test_changes
        old = [student('max.mustermann@x', 'Max', 'Mustermann', '5a').merge(:bildungsgang => :altsprachlich, :geschlecht => 'm'),
               student('mia.mustermann@x', 'Mia', 'Mustermann', '5a', nil).merge(:bildungsgang => :sesb),
               student('ida.alt@x', 'Ida', 'Alt', '5a', '2014-04-04').merge(:official_first_name => 'Ida Maria')]
        new = [student('max.mustermann@x', 'Maximilian', 'Mustermann', '5a').merge(:official_first_name => 'Max', :bildungsgang => :regulaer, :geschlecht => 'd'),
               student('mia.mustermann@x', 'Mia', 'Mustermann', '5a', '2014-02-02').merge(:bildungsgang => :sesb),
               student('ida.alt@x', 'Ida', 'Alt', '5a', '2014-05-05').merge(:official_first_name => 'Ida Marie')]
        d = @main.datenpflege_diff(old, new)
        changes = d[:changed].to_h { |o, n, ch| [n[:email], ch] }
        assert_equal [['Rufname', 'Max', 'Maximilian'], ['Bildungsgang', 'altsprachlich', 'regulaer'], ['Geschlecht', 'm', 'd']],
                     changes['max.mustermann@x']
        assert_equal [['Vornamen', 'Ida Maria', 'Ida Marie'], ['Geburtstag', '04.04.2014', '05.05.2014']], changes['ida.alt@x']
        # a birthday that was missing is no change, only counted
        refute changes.key?('mia.mustermann@x')
        assert_equal 1, d[:birthdays_added]
    end

    def test_word_diff_marks_only_what_changed
        # inline: what stays once and plain, only what differs marked
        assert_equal "Anna <del class='dp-old'>Maria</del><ins class='dp-new'>Marie</ins>",
                     @main.datenpflege_word_diff('Anna Maria', 'Anna Marie')
        # a second first name: just that name, not the whole value again
        assert_equal "Anna <ins class='dp-new'>Maria</ins>", @main.datenpflege_word_diff('Anna', 'Anna Maria')
        assert_equal "Anna <del class='dp-old'>Maria</del> Luise", @main.datenpflege_word_diff('Anna Maria Luise', 'Anna Luise')
        assert_equal "Mustermann<ins class='dp-new'>-Neu</ins>", @main.datenpflege_word_diff('Mustermann', 'Mustermann-Neu')
        # nothing in common: the whole value
        assert_equal "<del class='dp-old'>Max Peter</del><ins class='dp-new'>Paul Otto</ins>",
                     @main.datenpflege_word_diff('Max Peter', 'Paul Otto')
        assert_includes @main.datenpflege_word_diff('', 'x'), 'leer'
        assert_equal "<del class='dp-old'>&lt;b&gt;</del><ins class='dp-new'>b</ins>", @main.datenpflege_word_diff('<b>', 'b')
    end

    def lusd(row, nachname, vorname, geburtsdatum, rufname = nil)
        LusdImport::Student.new(row: row, nachname: nachname, vorname: vorname, geburtsdatum: geburtsdatum,
                                rufname: rufname, klasse: '5a', lusd_klasse: '5a', geschlecht: 'm')
    end

    # whoever is already in the dashboard keeps the address, also when LUSD
    # spells the name differently; twins are told apart by the full name; the
    # same name is the same person, even with another birthday
    def test_match_old
        old = [student('max.mustermann@x', 'Max', 'Mustermann', '5a', '2014-01-01'),
               student('tom.zwilling@x', 'Tom', 'Zwilling', '5a', '2014-03-03'),
               student('tim.zwilling@x', 'Tim', 'Zwilling', '5a', '2014-03-03'),
               student('ida.anders@x', 'Ida', 'Anders', '5a', '2014-04-04')]
        new = [lusd(2, 'Mustermann-Neu', 'Max Peter', '01.01.2014'),
               lusd(3, 'Zwilling', 'Tim', '03.03.2014'),
               lusd(4, 'Zwilling', 'Tom', '03.03.2014'),
               lusd(5, 'Anders', 'Ida', '05.05.2014')]
        m = @main.datenpflege_match_old(new, old)
        assert_equal({ 2 => 'max.mustermann@x', 3 => 'tim.zwilling@x', 4 => 'tom.zwilling@x', 5 => 'ida.anders@x' }, m.transform_values { |r, _| r[:email] })
    end

    # the old list often has no birthday: then the name decides, and the
    # address the dashboard would build counts as a match
    def test_match_old_without_birthday
        old = [student('lea.neu@x', 'Lea', 'Neu', '5a', nil), student('ben.alt@x', 'Ben', 'Alt', '5a', nil)]
        new = [lusd(2, 'Neu', 'Lea Marie', '01.01.2015'), lusd(3, 'Alt', 'Ben', '02.02.2015')]
        m = @main.datenpflege_match_old(new, old)
        assert_equal({ 2 => ['lea.neu@x', :name], 3 => ['ben.alt@x', :name] }, m.transform_values { |r, how| [r[:email], how] })
    end

    def test_new_email_leaves_out_name_parts
        parser = Parser.new
        domain = "@#{SCHUL_MAIL_DOMAIN}"
        email, note = @main.datenpflege_new_email(parser, 'Max', 'Mustermann', Set.new)
        assert_equal "max.mustermann#{domain}", email
        assert_nil note
        email, note = @main.datenpflege_new_email(parser, 'Anna-Katharina', 'von Schneiderhahn-Oberhofer', Set.new)
        assert_operator email.split('@').first.size, :<=, 23
        assert_equal "anna-katharina.von.schneiderhahn-oberhofer#{domain}", note
        assert_equal "anna.schneiderhahn#{domain}", email
        # never someone else's address
        email, _ = @main.datenpflege_new_email(parser, 'Max', 'Mustermann', Set.new(["max.mustermann#{domain}"]))
        assert_equal "max.mustermann.2#{domain}", email
    end

    def test_preview_escapes_names
        old = [student('a@x', 'Anna', 'Alt', '5a')]
        new = [student('b@x', '<b>Bo</b>', 'Neu', '5a', '2015-01-01')]
        c = { :filename => '<x>.csv', :total => 1, :errors => [], :old_path => '/data/schueler/ASCII.TXT',
              :mapping => { '5a' => { :target => '5a', :dashboard => '5a', :count => 1, :suggestion => nil } } }
        c.merge!(@main.datenpflege_diff(old, new))
        html = @main.datenpflege_preview_html(c)
        refute_includes html, '<b>Bo</b>'
        refute_includes html, '<x>'
        assert_includes html, '&lt;b&gt;Bo&lt;/b&gt;'
    end
end
