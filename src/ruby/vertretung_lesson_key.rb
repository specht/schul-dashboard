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
end
