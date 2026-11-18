# The subject code of a course as the timetable labels show it. The
# Vertretungsplan names a course that only exists there (an exam, an extra
# lesson) by its course key, e.g. 'agr_22'; the subject list knows 'agr'.
module FachCode
    # code: 'agr_22', 'Ma', … – faecher: code → name, lesson_keys: key → {:fach => …}
    def self.normalize(code, faecher, lesson_keys = {})
        return code if code.nil? || code.empty? || faecher.include?(code)
        info = lesson_keys[code]
        return info[:fach] if info && info[:fach]
        base = code.split('_').first
        return base if base && base != code && faecher.include?(base)
        code
    end
end
