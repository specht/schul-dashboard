require 'set'
require_relative 'test_helper'
require_app 'student_lessons'

# Students see their own courses only – in every grade, also for entries of
# the Vertretungsplan that match no lesson of the timetable.
class StudentLessonsTest < Minitest::Test
    OBERSTUFE = Set.new(['AGR_21_12', 'ma_21_12', 'PHY_11~12'])
    ZEHN = Set.new(['De_10a', 'Ma_10a', 'WF Frz_10a~10b~10c'])

    def test_own_courses_stay
        refute StudentLessons.foreign?({ :lesson_key => 'AGR_21_12', :orig_lesson_key => 'AGR_21_12' }, OBERSTUFE)
        # a cancelled lesson: no course any more, its course kept
        refute StudentLessons.foreign?({ :lesson_key => 0, :orig_lesson_key => 'PHY_11~12' }, OBERSTUFE)
    end

    def test_other_courses_go
        refute StudentLessons.foreign?({ :lesson_key => 'BI_21_12', :orig_lesson_key => 'BI_21_12' }, Set.new(['BI_21_12']))
        assert StudentLessons.foreign?({ :lesson_key => 'BI_21_12', :orig_lesson_key => 'BI_21_12' }, OBERSTUFE)
    end

    # a cancelled course of the Vertretungsplan ('DE_21' -> nil) that matches
    # no lesson: no course (0), but about DE_21_12 – everybody in 12 saw it
    def test_vertretungsplan_entry_of_another_course
        assert StudentLessons.foreign?({ :lesson_key => 0, :orig_lesson_key => 'DE_21_12' }, OBERSTUFE)
    end

    # grade 10: every student saw every elective
    def test_electives_in_10
        assert StudentLessons.foreign?({ :lesson_key => 'In_10a~10b~10c~10e', :orig_lesson_key => 'In_10a~10b~10c~10e' }, ZEHN)
        refute StudentLessons.foreign?({ :lesson_key => 'WF Frz_10a~10b~10c', :orig_lesson_key => 'WF Frz_10a~10b~10c' }, ZEHN)
    end

    # a lesson moved to another course: who takes the new course sees it too
    def test_lesson_moved_to_an_own_course
        refute StudentLessons.foreign?({ :lesson_key => 'ma_21_12', :orig_lesson_key => 'geo_21_12' }, OBERSTUFE)
    end

    # nobody knows whose they are: they stay, as before
    def test_lessons_of_no_course_stay
        refute StudentLessons.foreign?({ :lesson_key => 0, :orig_lesson_key => nil }, OBERSTUFE)
        refute StudentLessons.foreign?({ :lesson_key => 'X_1' }, nil)
    end
end
