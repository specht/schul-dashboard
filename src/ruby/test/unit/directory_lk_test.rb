require_relative 'test_helper'

# The LKs of students in 11/12 in the directory (include/directory.rb): the
# school's short code of the subject (»DE« is »Deutsch LK«, Deutsch is »D«),
# alphabetical in a class list, the LK's own first in its list. Made-up
# courses and students.
class DirectoryLkTest < Minitest::Test
    def setup
        skip 'needs the test stack (./test.sh unit)' unless in_test_stack?
        # directory.rb extends Prawn (main.rb loads it)
        require 'prawn'
        Dir.chdir(APP_ROOT) do
            require_app 'design_tokens'
            require_app 'include/schuelerliste'
            require_app 'include/directory'
        end
        # made-up data for this test only (teardown puts back what was there)
        @saved = [:@@faecher, :@@lessons, :@@schueler_for_lesson].to_h do |v|
            [v, Main.class_variable_defined?(v) ? Main.class_variable_get(v) : :undefined]
        end
        Main.class_variable_set(:@@faecher, { 'DE' => 'Deutsch LK', 'D' => 'Deutsch', 'MA' => 'Mathematik LK', 'Ma' => 'Mathematik' })
        Main.class_variable_set(:@@lessons, { :lesson_keys => {
            'DE-L1_11' => { :fach => 'DE', :orig_fach => 'DE-L1', :klassen => ['11'] },
            'MA-L2_11' => { :fach => 'MA', :orig_fach => 'MA-L2', :klassen => ['11'] },
            'XY-L3_11' => { :fach => 'XY', :orig_fach => 'XY-L3', :klassen => ['11'] },
            'ma_11' => { :fach => 'ma', :orig_fach => 'ma', :klassen => ['11'] },
        } })
        Main.class_variable_set(:@@schueler_for_lesson, {
            'DE-L1_11' => ['a@x'], 'MA-L2_11' => ['a@x', 'b@x'], 'XY-L3_11' => ['a@x'], 'ma_11' => ['c@x'],
        })
        @main = Main.allocate
    end

    def teardown
        (@saved || {}).each do |v, value|
            if value == :undefined
                Main.remove_class_variable(v)
            else
                Main.class_variable_set(v, value)
            end
        end
    end

    def test_short_codes_alphabetical_and_the_lks_own_first
        lks = @main.directory_lks
        # a GK is no LK; an unknown code stays as it is, capitalised
        assert_equal ['D', 'Ma', 'Xy'], lks['a@x'].map { |x| x[:label] }
        assert_equal ['Deutsch', 'Mathematik', 'Xy'], lks['a@x'].map { |x| x[:name] }
        assert_equal ['Ma'], lks['b@x'].map { |x| x[:label] }
        assert_equal [], lks['c@x']
        # in the list of the Mathematik LK: Mathematik first, the rest as before
        assert_equal ['Ma', 'D', 'Xy'], @main.directory_lks_of(lks, 'a@x', 'MA-L2_11').map { |x| x[:label] }
        assert_equal ['D', 'Ma', 'Xy'], @main.directory_lks_of(lks, 'a@x', '11').map { |x| x[:label] }
    end
end
