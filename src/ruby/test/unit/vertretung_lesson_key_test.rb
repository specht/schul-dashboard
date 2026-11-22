require_relative 'test_helper'
require_app 'vertretung_lesson_key'

# When the Vertretungsplan changes a lesson's subject, the lesson moves to the
# new subject's course: its homework and lesson count go with the course key.
class VertretungLessonKeyTest < Minitest::Test
    LESSONS_FOR_KLASSE = {
        '9c' => ['Ma_9c', 'AGr_9c', 'AGr_9c~9o', 'La_9c', 'WF Frz_9c~9l'],
        '9o' => ['AGr_9c~9o', 'Ma_9o'],
    }
    LESSON_KEYS = {
        'Ma_9c' => { :klassen => ['9c'], :lehrer => ['Sp'] },
        'AGr_9c' => { :klassen => ['9c'], :lehrer => ['Ku'] },
        'AGr_9c~9o' => { :klassen => ['9c', '9o'], :lehrer => ['Ku'] },
        'La_9c' => { :klassen => ['9c'], :lehrer => ['Lt'] },
        'Ma_9o' => { :klassen => ['9o'], :lehrer => ['Mx'] },
    }

    def key(fach, klassen, lehrer, lessons = LESSON_KEYS, ds: '2026-11-23', klassen_alt: nil)
        VertretungLessonKey.for(ds, fach, klassen, klassen_alt, lehrer, LESSONS_FOR_KLASSE, lessons)
    end

    def test_single_course
        assert_equal 'Ma_9c', key('Ma', ['9c'], ['Sp'])
    end

    # Ma and AGr swapped in 9c: 9c has AGr alone and together with 9o. The
    # lesson kept the maths key before and showed the maths homework.
    def test_course_for_exactly_these_classes
        assert_equal 'AGr_9c', key('AGr', ['9c'], ['Ku'])
        assert_equal 'AGr_9c~9o', key('AGr', ['9c', '9o'], ['Ku'])
    end

    def test_course_of_the_teacher
        lessons = LESSON_KEYS.merge('AGr_9c~9o' => { :klassen => ['9c'], :lehrer => ['Zz'] })
        assert_equal 'AGr_9c~9o', key('AGr', ['9c'], ['Zz'], lessons)
    end

    # never the old subject's course when it can't tell
    def test_ambiguous_is_no_course
        lessons = LESSON_KEYS.merge('AGr_9c~9o' => { :klassen => ['9c'], :lehrer => ['Ku'] })
        assert_equal 0, key('AGr', ['9c'], ['Ku'], lessons)
    end

    # a stand-in lesson in a subject the class doesn't have: the caller keeps the key
    def test_no_course_of_that_subject
        assert_nil key('De', ['9c'], ['Sp'])
        assert_nil key('AGr', nil, nil)
    end

    def test_old_classes_when_no_new_ones
        assert_equal 'AGr_9c', key('AGr', nil, ['Ku'], klassen_alt: ['9c'])
    end

    # lessons are numbered per course and their contents stored by number:
    # before SINCE the old rule stays, or contents entered long ago would move
    def test_old_rule_before_since
        assert_nil key('AGr', ['9c'], ['Ku'], ds: '2026-11-20')
        assert_nil key('AGr', nil, ['Ku'], ds: '2026-11-20', klassen_alt: ['9c'])
        assert_equal 'Ma_9c', key('Ma', ['9c'], ['Sp'], ds: '2026-09-25')
    end

    # entries of the Vertretungsplan that match no lesson: their course, so
    # that only its students see them (11/12 name courses by code)
    CODES = { 'DE_21' => ['DE_21_12'], 'BI_21' => ['BI_21_12'], 'MA' => ['MA_11~12'], 'AGr' => ['AGr_9c', 'AGr_9c~9o'] }
    COURSES = {
        'DE_21_12' => { :klassen => ['12'] }, 'BI_21_12' => { :klassen => ['12'] },
        'MA_11~12' => { :klassen => ['11', '12'] },
        'AGr_9c' => { :klassen => ['9c'] }, 'AGr_9c~9o' => { :klassen => ['9c', '9o'] },
    }

    def course(codes, klassen)
        VertretungLessonKey.course_of_entry(codes, klassen, CODES, COURSES)
    end

    def test_course_of_entry
        assert_equal 'DE_21_12', course(['DE_21', nil], ['12'])
        assert_equal 'BI_21_12', course([nil, 'BI_21'], ['12'])
        assert_equal 'MA_11~12', course(['MA', nil], ['11', '12'])
        # the old course first
        assert_equal 'DE_21_12', course(['DE_21', 'BI_21'], ['12'])
    end

    def test_course_of_entry_unknown_or_unclear
        assert_nil course(['XY_1', nil], ['12'])
        assert_nil course(['DE_21', nil], ['11'])
        assert_nil course(['AGr', nil], ['9c'])
        assert_nil course([nil, nil], ['12'])
    end
end
