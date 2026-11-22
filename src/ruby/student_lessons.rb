# Which lessons of a class a student sees in the timetable (timetable.rb):
# the student's own courses – courses in 11/12, electives (wahlpflicht.yaml),
# girls' and boys' sport (@@lessons_for_user). This was checked for 11/12
# only: in 10 everybody saw every elective, and entries of the
# Vertretungsplan that match no lesson (a moved or cancelled course, an exam)
# showed in every timetable of the class.
module StudentLessons
    # event: a lesson of the timetable (:orig_lesson_key – its course, kept
    # for cancelled lessons and Vertretungsplan entries about a course;
    # :lesson_key – the course it belongs to now), own: the student's courses.
    # Lessons of no course (key 0 or nil) stay: nobody knows whose they are.
    def self.foreign?(event, own)
        return false if own.nil?
        keys = [event[:orig_lesson_key], event[:lesson_key]].reject { |k| k.nil? || k == 0 }
        !keys.empty? && keys.none? { |k| own.include?(k) }
    end
end
