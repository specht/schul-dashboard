# Which course a lesson belongs to after the Vertretungsplan changed its
# subject (e.g. Ma → AGr when two lessons are swapped). The lesson's homework,
# notes and lesson count follow this course key, so a wrong guess shows one
# course's homework in another course's lesson.
module VertretungLessonKey
    # Lessons are numbered per course from the start of the school year and
    # their contents are stored by that number: a new rule for past days would
    # move contents that were entered long ago. So it holds from this day on.
    SINCE = '2026-11-23'

    # ds: the day, fach_neu: the new subject ('AGr'), klassen_neu / klassen_alt:
    # the classes of the changed lesson, lehrer: its new teachers,
    # lessons_for_klasse: klasse → [key], lesson_keys: key → {:klassen, :lehrer}.
    # Returns the course key; 0 (no course) when several courses of that
    # subject fit and none stands out; nil to keep the lesson's key (no course
    # of that subject: a stand-in lesson).
    def self.for(ds, fach_neu, klassen_neu, klassen_alt, lehrer, lessons_for_klasse, lesson_keys)
        klassen = ds >= SINCE ? (klassen_neu || klassen_alt) : klassen_neu
        candidates = (klassen || []).map { |klasse| lessons_for_klasse[klasse] || [] }.flatten.uniq.select do |key|
            key.split('_').first == fach_neu
        end
        return candidates.first if candidates.size == 1
        # before SINCE: only a single course of that subject, else the old key
        return nil if candidates.empty? || ds < SINCE
        # several courses of that subject (9c alone and 9c with 9o): the one
        # for exactly these classes …
        exact = candidates.select do |key|
            ((lesson_keys[key] || {})[:klassen] || []).sort == klassen.sort
        end
        return exact.first if exact.size == 1
        candidates = exact unless exact.empty?
        # … or the one these teachers teach
        taught = candidates.select do |key|
            !((((lesson_keys[key] || {})[:lehrer]) || []) & (lehrer || [])).empty?
        end
        return taught.first if taught.size == 1
        0
    end

    # The course an entry of the Vertretungsplan is about that matches no
    # lesson in the timetable (a moved or cancelled course, an exam): the
    # Vertretungsplan names courses of 11/12 by their code ('DE_21'), the
    # timetable knows them as 'DE_21_12'. Only for who sees the entry
    # (students see their own courses only), not for its lesson count.
    # codes: [fach_alt, fach_neu], klassen: the entry's classes,
    # course_keys_for_code: code → [key] (@@original_lesson_key_for_lesson_key).
    # The old course first (a cancelled or replaced course concerns its
    # students), else the new one. Returns the key, or nil when none or
    # several fit.
    def self.course_of_entry(codes, klassen, course_keys_for_code, lesson_keys)
        klassen = klassen || []
        (codes || []).compact.each do |code|
            keys = (course_keys_for_code[code] || []).to_a.uniq.select do |key|
                !(((lesson_keys[key] || {})[:klassen] || []) & klassen).empty?
            end
            return keys.first if keys.size == 1
        end
        nil
    end
end
