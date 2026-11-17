require_relative 'test_helper'
require_app 'fach_code'

# A course only in the Vertretungsplan comes as its course key ('agr_22');
# its label should show the subject, like the regular timetable does.
class FachCodeTest < Minitest::Test
    FAECHER = { 'agr' => 'Altgriechisch GK', 'Ma' => 'Mathematik', 'In' => 'Informatik' }

    def test_known_codes_stay
        assert_equal 'Ma', FachCode.normalize('Ma', FAECHER)
    end

    def test_course_key_becomes_its_subject
        assert_equal 'agr', FachCode.normalize('agr_22', FAECHER)
        assert_equal 'In', FachCode.normalize('IN-L223', FAECHER, { 'IN-L223' => { :fach => 'In' } })
    end

    def test_unknown_codes_stay
        assert_equal 'xyz_1', FachCode.normalize('xyz_1', FAECHER)
        assert_nil FachCode.normalize(nil, FAECHER)
        assert_equal '', FachCode.normalize('', FAECHER)
    end
end
