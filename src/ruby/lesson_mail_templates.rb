require 'cgi'

# Texts of the mails teachers send to parents from a lesson ("Mails aus dem
# Unterricht", timetable → Mail). Admins can change them on
# /unterrichtsmails; a changed text is stored as
# (:LessonMailTemplate {reason, subject, body}), the defaults below apply
# otherwise. The mail bot and the preview both render through
# LessonMailTemplates.render, so the preview shows exactly what gets sent.
#
# Placeholders: {Vorname}, {Name}, {Klasse}, {Fach}, {Notiz}, {Lehrkraft}
# (who sends the mail and gets the replies – for Otium mails the teacher on
# Otium duty), {Lehrkraft der Stunde} (the lesson's teacher, e.g. »Herr
# Clarke«).
# {männlich|weiblich} picks the first text for boys, the second otherwise
# (as before: everything that is not 'm' gets the second text).
# In the body, a blank line starts a new paragraph, a single line break
# becomes a line break.
module LessonMailTemplates
    REASONS = %w(material homework signature disturbance disturbance_otium late praise).freeze

    LABELS = {
        'material' => 'Material fehlt',
        'homework' => 'Hausaufgaben fehlen',
        'signature' => 'Unterschrift fehlt',
        'disturbance' => 'Störverhalten',
        'disturbance_otium' => 'Störverhalten (Otium)',
        'late' => 'Verspätung',
        'praise' => 'Besonderes Lob',
    }.freeze

    # example notes for the preview, as in the timetable's mail dialog
    EXAMPLE_NOTES = {
        'material' => 'Zirkel fehlt',
        'homework' => 'S. 23, Nr. 4',
        'signature' => 'Anmeldung Klassenfahrt',
        'late' => '10 Minuten',
    }.freeze

    PLACEHOLDERS = {
        'Vorname' => 'Vorname des Kindes',
        'Name' => 'Vor- und Nachname des Kindes',
        'Klasse' => 'Klasse des Kindes',
        'Fach' => 'Fach der Stunde',
        'Notiz' => 'Notiz der Lehrkraft in Klammern, z. B. » (Zirkel fehlt)« – mit Leerzeichen davor; ohne Notiz entfällt sie',
        'Lehrkraft' => 'Name der Lehrkraft, die die Mail schickt (bei Otium-Mails die Otium-Aufsicht); sie bekommt auch die Antworten',
        'Lehrkraft der Stunde' => 'Lehrkraft der Stunde, z. B. »Herr Clarke« – bei Otium-Mails die Lehrkraft, die das Kind ins Otium geschickt hat',
    }.freeze

    MAX_SUBJECT_LENGTH = 200
    MAX_BODY_LENGTH = 5000

    DEFAULTS = {
        'material' => {
            :subject => 'Fehlendes Arbeitsmaterial im Fach {Fach}',
            :body => <<~END_OF_TEXT,
                Liebe Eltern,

                {Ihr Sohn|Ihre Tochter} {Vorname} hat heute im Fach {Fach} das Arbeitsmaterial nicht oder nicht vollständig dabei gehabt{Notiz}. Bitte üben Sie mit {Vorname}, die Schultasche sorgfältig zu packen.

                Mit freundlichen Grüßen
                {Lehrkraft}
            END_OF_TEXT
        },
        'homework' => {
            :subject => 'Fehlende Hausaufgaben im Fach {Fach}',
            :body => <<~END_OF_TEXT,
                Liebe Eltern,

                {Ihr Sohn|Ihre Tochter} {Vorname} hat heute im Fach {Fach} die Hausaufgaben nicht oder nicht vollständig vorlegen können{Notiz}. Bitte sprechen auch Sie mit {Vorname} über die Notwendigkeit, die Hausaufgaben sorgfältig und vollständig anzufertigen und mitzubringen.

                Mit freundlichen Grüßen
                {Lehrkraft}
            END_OF_TEXT
        },
        'signature' => {
            :subject => 'Fehlende Unterschrift',
            :body => <<~END_OF_TEXT,
                Liebe Eltern,

                {Ihr Sohn|Ihre Tochter} {Vorname} hat heute eine geforderte Unterschrift nicht vorlegen können{Notiz}. Bitte geben Sie diese Ihrem Kind morgen mit.

                Mit freundlichen Grüßen
                {Lehrkraft}
            END_OF_TEXT
        },
        'disturbance' => {
            :subject => 'Störverhalten',
            :body => <<~END_OF_TEXT,
                Liebe Eltern,

                {Ihr Sohn|Ihre Tochter} {Vorname} fiel heute im Fach {Fach} durch Störverhalten und Unaufmerksamkeit auf{Notiz}. Dies hatte nicht nur negative Folgen für {seine|ihre} eigene Konzentration, sondern war auch zum Nachteil für die gesamte Klasse. Bitte sprechen Sie mit {Vorname} über die Notwendigkeit, dem Unterricht aufmerksam zu folgen und Störverhalten im Unterricht zu unterlassen.

                Mit freundlichen Grüßen
                {Lehrkraft}
            END_OF_TEXT
        },
        'disturbance_otium' => {
            :subject => 'Störverhalten (Otium)',
            :body => <<~END_OF_TEXT,
                Liebe Eltern,

                {Ihr Sohn|Ihre Tochter} {Vorname} zeigte heute im Fach {Fach} ein derart ausgeprägtes Störverhalten{Notiz}, dass {Lehrkraft der Stunde} {ihn|sie} im Sinne {seiner|ihrer} Mitschüler:innen als pädagogische Maßnahme vorübergehend vom Unterricht ausschließen musste.

                {Er|Sie} hat die Zeit im Otium verbracht und muss die versäumten Unterrichtsinhalte selbständig nacharbeiten. Bitte sprechen Sie eingehend mit {Vorname} über die Konsequenzen {seines|ihres} Verhaltens.

                Mit freundlichen Grüßen
                {Lehrkraft}
            END_OF_TEXT
        },
        'late' => {
            :subject => 'Verspätung',
            :body => <<~END_OF_TEXT,
                Liebe Eltern,

                {Ihr Sohn|Ihre Tochter} {Vorname} hat heute im Fach {Fach} einen Klassenbucheintrag aufgrund einer Verspätung erhalten{Notiz}.

                Bitte beachten Sie, dass diese E-Mail nur eine einzelfallbezogene Rückmeldung darstellt und sich daraus kein Anspruch auf die vollständige Meldung vergangener und zukünftiger Verspätungen ergibt.

                Mit freundlichen Grüßen
                {Lehrkraft}
            END_OF_TEXT
        },
        'praise' => {
            :subject => 'Lob',
            :body => <<~END_OF_TEXT,
                Liebe Eltern,

                ich freue mich, Ihnen mitteilen zu können, dass {Ihr Sohn|Ihre Tochter} {Vorname} heute im Fach {Fach} durch besonders erwähnenswerte positive Leistungen aufgefallen ist{Notiz}. Bitte loben Sie {ihn|sie} für {sein|ihr} Engagement und {seine|ihre} Leistungsbereitschaft.

                Mit freundlichen Grüßen
                {Lehrkraft}
            END_OF_TEXT
        },
    }.freeze

    TOKEN = /\{([^{}]*)\}/

    def self.placeholder_name(inner)
        wanted = inner.strip.gsub(/\s+/, ' ').downcase
        PLACEHOLDERS.keys.find { |name| name.downcase == wanted }
    end

    # German error messages for a subject or body, empty if it is fine
    def self.errors(text, field)
        text = text.to_s
        errors = []
        errors << "#{field} ist leer." if text.strip.empty?
        text.scan(TOKEN).each do |(inner)|
            if inner.include?('|')
                if inner.split('|', -1).size != 2
                    errors << "#{field}: {#{inner}} braucht genau zwei Texte, getrennt durch einen Strich: {männlich|weiblich}."
                end
            elsif placeholder_name(inner).nil?
                errors << "#{field}: Den Platzhalter {#{inner}} gibt es nicht."
            end
        end
        rest = text.gsub(TOKEN, '')
        if rest.include?('{') || rest.include?('}')
            errors << "#{field}: Eine geschweifte Klammer ist nicht geschlossen oder steht allein."
        end
        errors.uniq
    end

    def self.template_errors(subject, body)
        errors = self.errors(subject, 'Betreff') + self.errors(body, 'Text')
        errors << "Der Betreff ist zu lang (höchstens #{MAX_SUBJECT_LENGTH} Zeichen)." if subject.to_s.size > MAX_SUBJECT_LENGTH
        errors << "Der Text ist zu lang (höchstens #{MAX_BODY_LENGTH} Zeichen)." if body.to_s.size > MAX_BODY_LENGTH
        errors
    end

    # vars: :first_name, :name, :klasse, :fach, :note, :teacher, :lesson_teacher, :geschlecht
    def self.values(vars)
        note = vars[:note].to_s.gsub(/\s+/, ' ').strip
        {
            'Vorname' => vars[:first_name],
            'Name' => vars[:name],
            'Klasse' => vars[:klasse],
            'Fach' => vars[:fach],
            'Notiz' => note.empty? ? '' : " (#{note})",
            'Lehrkraft' => vars[:teacher],
            'Lehrkraft der Stunde' => vars[:lesson_teacher],
        }.transform_values { |v| v.to_s.gsub(/\s+/, ' ') }
    end

    def self.fill(text, vars)
        values = self.values(vars)
        text.to_s.gsub(/\r\n?/, "\n").gsub(TOKEN) do
            inner = $1
            if inner.include?('|')
                # {männlich|weiblich} or {männlich|weiblich|divers}; without
                # a third form divers students get both: "er/sie"
                male, female, divers = inner.split('|', 3)
                case vars[:geschlecht]
                when 'm' then male
                when 'd' then divers || "#{male}/#{female}"
                else female
                end
            else
                name = placeholder_name(inner)
                name ? values[name] : "{#{inner}}"
            end
        end
    end

    # template: {:subject, :body}; returns {:subject (plain text), :html}
    def self.render(template, vars)
        subject = fill(template[:subject], vars).gsub(/\s+/, ' ').strip
        paragraphs = fill(template[:body], vars).strip.split(/\n[ \t]*\n\s*/)
        html = paragraphs.map do |paragraph|
            lines = paragraph.split("\n").map { |line| CGI.escapeHTML(line.strip) }
            "<p>#{lines.join("<br>\n")}</p>\n"
        end.join('')
        {:subject => subject, :html => html}
    end

    # stored: {reason => {:subject, :body}} from the database
    def self.effective(stored, reason)
        entry = (stored || {})[reason]
        if entry && !entry[:subject].to_s.strip.empty? && !entry[:body].to_s.strip.empty?
            {:subject => entry[:subject], :body => entry[:body]}
        else
            DEFAULTS[reason]
        end
    end
end
