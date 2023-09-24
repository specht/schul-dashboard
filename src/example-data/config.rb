WECHSELUNTERRICHT_KLASSENSTUFEN = []
KLASSEN_TR = {'9o' => '9ω'}
TIMETABLE_ENTRIES_VISIBLE_AHEAD_DAYS = 7
AUFSICHT_ZEIT = {
    # 1 bedeutet: vor der 1. Stunde
    # endet die Aufsicht um 8:35
    1 => '08:35',
}

KLASSEN_ORDER = ['5a', '5b', '5c', '11', '12']

# Definition von Wechselwochen
SWITCH_WEEKS = {'2021-08-09' => nil}

class Main < Sinatra::Base
    def self.fix_stundenzeiten
        hd = '2021-08-09'
        HOURS_FOR_KLASSE[hd] = {}
        @@klassen_order.each do |klasse|
            klassenstufe = klasse.to_i
            HOURS_FOR_KLASSE[hd][klasse] = []
            if [5, 6].include?(klassenstufe)
                HOURS_FOR_KLASSE[hd][klasse] << ['07:45', '08:30']
                HOURS_FOR_KLASSE[hd][klasse] << ['08:35', '09:15']
                HOURS_FOR_KLASSE[hd][klasse] << ['09:20', '10:00']
                HOURS_FOR_KLASSE[hd][klasse] << ['10:15', '10:55']
                HOURS_FOR_KLASSE[hd][klasse] << ['11:00', '11:40']
                HOURS_FOR_KLASSE[hd][klasse] << ['11:40', '12:20']
                HOURS_FOR_KLASSE[hd][klasse] << ['13:00', '13:40']
                HOURS_FOR_KLASSE[hd][klasse] << ['13:45', '14:25']
                HOURS_FOR_KLASSE[hd][klasse] << ['14:30', '15:15']
                HOURS_FOR_KLASSE[hd][klasse] << ['15:20', '16:05']
                HOURS_FOR_KLASSE[hd][klasse] << ['16:10', '16:55']
                HOURS_FOR_KLASSE[hd][klasse] << ['16:55', '17:40']
            elsif [7, 8, 9, 10].include?(klassenstufe)
                HOURS_FOR_KLASSE[hd][klasse] << ['07:45', '08:30']
                HOURS_FOR_KLASSE[hd][klasse] << ['08:35', '09:15']
                HOURS_FOR_KLASSE[hd][klasse] << ['09:20', '10:00']
                HOURS_FOR_KLASSE[hd][klasse] << ['10:00', '10:40']
                HOURS_FOR_KLASSE[hd][klasse] << ['11:00', '11:40']
                HOURS_FOR_KLASSE[hd][klasse] << ['11:40', '12:20']
                HOURS_FOR_KLASSE[hd][klasse] << ['12:25', '13:05']
                HOURS_FOR_KLASSE[hd][klasse] << ['13:45', '14:25']
                HOURS_FOR_KLASSE[hd][klasse] << ['14:30', '15:15']
                HOURS_FOR_KLASSE[hd][klasse] << ['15:20', '16:05']
                HOURS_FOR_KLASSE[hd][klasse] << ['16:10', '16:55']
                HOURS_FOR_KLASSE[hd][klasse] << ['16:55', '17:40']
            else
                HOURS_FOR_KLASSE[hd][klasse] << ['07:45', '08:30']
                HOURS_FOR_KLASSE[hd][klasse] << ['08:35', '09:15']
                HOURS_FOR_KLASSE[hd][klasse] << ['09:30', '10:10']
                HOURS_FOR_KLASSE[hd][klasse] << ['10:10', '10:50']
                HOURS_FOR_KLASSE[hd][klasse] << ['10:55', '11:35']
                HOURS_FOR_KLASSE[hd][klasse] << ['11:35', '12:15']
                HOURS_FOR_KLASSE[hd][klasse] << ['12:50', '13:30']
                HOURS_FOR_KLASSE[hd][klasse] << ['13:35', '14:15']
                HOURS_FOR_KLASSE[hd][klasse] << ['14:30', '15:15']
                HOURS_FOR_KLASSE[hd][klasse] << ['15:20', '16:05']
                HOURS_FOR_KLASSE[hd][klasse] << ['16:10', '16:55']
                HOURS_FOR_KLASSE[hd][klasse] << ['16:55', '17:40']
            end
        end
    end

    def self.fix_lesson_key_tr(lesson_key_tr)
        # Hier können lesson keys zusammengefasst werden,
        # was manchmal nötig ist, z. B.:
        # lesson_key_tr['Agr_8b'] = 'Agr_8b~8e'
        lesson_key_tr
    end

    def self.fix_lessons_for_shorthand
        # Wenn man man bestimmten Nutzer:innen Zugriff auf
        # die Stundenpläne bestimmter Klassen geben möchte,
        # die sich nicht aus dem Stundenplan ergeben,
        # dann kann man dies hier tun, z. B.:
        @@klassen_for_shorthand['_Sek'] = KLASSEN_ORDER
    end

    def self.fix_parsed_klasse(klasse)
        d = {}
        # Manchmal werden in Untis die Klassen anders bezeichnet,
        # hier können sie übersetzt werden, z. B.:
        # d = {'12' => '11', '13' => '12', '1WK' => 'WK', '2WK' => 'WK2', '4b' => 'WK2'}
        d[klasse] || klasse
    end
end

