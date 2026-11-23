require 'cgi'

# Texts of the mails teachers send to parents from a lesson ("Mails aus dem
# Unterricht", timetable → Mail). Admins can change them on
# /unterrichtsmails. Every text lives in the database as
# (:LessonMailTemplate {reason, subject, body}); the built-in reasons get
# their default text below once at startup (SetupDatabase in main.rb), which
# also stays the text of »Standardtext wiederherstellen« and the fallback
# should a node be missing. The mail bot and the preview both render through
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
        elsif custom_reason?(reason)
            # an own template has no default; the mail bot counts it as an error
            nil
        else
            DEFAULTS[reason]
        end
    end

    # is this the built-in default text of the reason?
    def self.default_text?(reason, subject, body)
        default = DEFAULTS[reason]
        return false if default.nil?
        subject.to_s.strip == default[:subject] && body.to_s.gsub(/\r\n?/, "\n").strip == default[:body].strip
    end

    # ------------------------------------------------------------------
    # Every reason is a (:LessonMailTemplate) node with its text and its rules:
    #   label              name in the timetable and the overviews
    #   color              colour in the class overview of sent mails
    #   status             'test', 'active' or 'hidden'
    #   sender             who sends it: 'teachers' or 'otium' (the teacher on
    #                      Otium duty, for the lesson the student came from)
    #   cc_klassenleitung  the class teachers get a copy
    #   note_hint          example for the note field, e.g. »Zirkel fehlt«
    # The built-in reasons get these once from BUILTIN_RULES at startup
    # (SetupDatabase in main.rb); after that the database decides.
    #
    # Own templates: admins add further reasons (reason 'eigen_…', custom:
    # true). A new one starts as 'test': only admins see it in the timetable,
    # and its mails go to the sender alone (marked as a test) instead of the
    # parents. 'active' sends them like any other, 'hidden' takes a reason
    # out of the timetable but keeps its name and colour for the mails already
    # sent. Mails remember at sending time whether they were a test
    # (Mail.test). Built-in reasons can be hidden, never be a test.

    CUSTOM_PREFIX = 'eigen_'
    STATUSES = %w(test active hidden).freeze
    STATUS_LABELS = {'test' => 'Test', 'active' => 'Aktiv', 'hidden' => 'Ausgeblendet'}.freeze
    SENDERS = %w(teachers otium).freeze
    MAX_LABEL_LENGTH = 60
    MAX_NOTE_HINT_LENGTH = 60
    DEFAULT_CUSTOM_COLOR = '#729fcf'

    BUILTIN_COLORS = {
        'material' => '#fce94f',
        'homework' => '#fcaf3e',
        'signature' => '#f57900',
        'disturbance' => '#ef2929',
        'disturbance_otium' => '#cc0000',
        'late' => '#7b67ae',
        'praise' => '#4aa03f',
    }.freeze

    # the rules the built-in reasons start with
    BUILTIN_RULES = Hash[REASONS.map do |reason|
        [reason, {
            :label => LABELS[reason],
            :color => BUILTIN_COLORS[reason],
            :status => 'active',
            :sender => reason == 'disturbance_otium' ? 'otium' : 'teachers',
            :cc_klassenleitung => reason == 'disturbance_otium',
            :note_hint => EXAMPLE_NOTES[reason] || '',
        }.freeze]
    end].freeze

    NEW_TEMPLATE_BODY = "Liebe Eltern,\n\n{Ihr Sohn|Ihre Tochter} {Vorname} …{Notiz}\n\nMit freundlichen Grüßen\n{Lehrkraft}"

    def self.custom_reason?(reason)
        !!(reason.to_s =~ /\A#{CUSTOM_PREFIX}[0-9a-z]{4,16}\z/)
    end

    def self.valid_color?(color)
        !!(color.to_s =~ /\A#[0-9a-fA-F]{6}\z/)
    end

    # black or white, whichever reads better on the colour
    def self.text_color(color)
        return '#000000' unless valid_color?(color)
        r, g, b = color[1, 6].scan(/../).map { |x| x.to_i(16) }
        (0.299 * r + 0.587 * g + 0.114 * b) > 150 ? '#000000' : '#ffffff'
    end

    # database rows (LessonMailTemplate nodes) → {reason => entry}; fields
    # not set are nil
    def self.from_nodes(nodes)
        result = {}
        nodes.each do |t|
            result[t[:reason]] = {
                :subject => t[:subject], :body => t[:body],
                :custom => t[:custom] == true, :label => t[:label], :color => t[:color],
                :status => t[:status], :sender => t[:sender],
                :cc_klassenleitung => t[:cc_klassenleitung], :note_hint => t[:note_hint],
                :ts_created => t[:ts_created], :ts_updated => t[:ts_updated], :updated_by => t[:updated_by],
            }
        end
        result
    end

    # the rules of one reason: what is stored, else what it started with
    def self.rules(reason, entry, custom)
        start = custom ? {:label => '', :color => DEFAULT_CUSTOM_COLOR, :status => 'test', :sender => 'teachers',
                          :cc_klassenleitung => false, :note_hint => ''} : BUILTIN_RULES[reason]
        entry ||= {}
        label = entry[:label].to_s.strip.empty? ? start[:label] : entry[:label].to_s
        color = valid_color?(entry[:color]) ? entry[:color] : start[:color]
        status = STATUSES.include?(entry[:status]) ? entry[:status] : start[:status]
        # a built-in reason is never a test
        status = 'active' if !custom && status == 'test'
        {
            :reason => reason, :custom => custom,
            :label => label, :color => color, :text_color => text_color(color), :status => status,
            :sender => SENDERS.include?(entry[:sender]) ? entry[:sender] : start[:sender],
            :cc_klassenleitung => entry[:cc_klassenleitung].nil? ? start[:cc_klassenleitung] : entry[:cc_klassenleitung] == true,
            :note_hint => entry[:note_hint].nil? ? start[:note_hint] : entry[:note_hint].to_s,
        }
    end

    # every reason in display order: the built-in ones, then the own ones by
    # age
    def self.catalog(stored)
        stored ||= {}
        list = REASONS.map { |reason| rules(reason, stored[reason], false) }
        stored.select { |reason, entry| entry[:custom] && custom_reason?(reason) }.sort_by do |reason, entry|
            [entry[:ts_created].to_i, reason]
        end.each do |reason, entry|
            list << rules(reason, entry, true)
        end
        list
    end

    def self.find(stored, reason)
        catalog(stored).find { |x| x[:reason] == reason }
    end

    # Can someone send a mail with this reason? Test templates only admins,
    # hidden ones nobody; reasons the Otium sends only the Otium.
    def self.sendable?(info, admin, otium = false)
        return false if info.nil?
        return false if info[:sender] == 'otium' && !otium
        info[:status] == 'active' || (info[:status] == 'test' && admin)
    end

    def self.label_errors(label, stored, own_reason = nil)
        label = label.to_s.strip
        errors = []
        errors << 'Der Name ist leer.' if label.empty?
        errors << "Der Name ist zu lang (höchstens #{MAX_LABEL_LENGTH} Zeichen)." if label.size > MAX_LABEL_LENGTH
        taken = catalog(stored).any? do |x|
            x[:reason] != own_reason && x[:label].to_s.strip.downcase == label.downcase
        end
        errors << "Eine Vorlage »#{label}« gibt es schon." if taken && !label.empty?
        errors
    end

    # German error messages for the rules of a reason (data: :label, :color,
    # :status, :sender, :cc_klassenleitung, :note_hint)
    def self.rule_errors(data, stored, own_reason, custom)
        errors = label_errors(data[:label], stored, own_reason)
        errors << 'Die Farbe ist ungültig.' unless valid_color?(data[:color])
        statuses = custom ? STATUSES : STATUSES - ['test']
        errors << 'Der Zustand ist ungültig.' unless statuses.include?(data[:status])
        errors << 'Ungültig, wer die Mail schickt.' unless SENDERS.include?(data[:sender])
        errors << 'Ungültige Angabe zur Klassenleitung.' unless [true, false].include?(data[:cc_klassenleitung])
        errors << "Der Hinweis zur Notiz ist zu lang (höchstens #{MAX_NOTE_HINT_LENGTH} Zeichen)." if data[:note_hint].to_s.strip.size > MAX_NOTE_HINT_LENGTH
        errors
    end

    # Who gets a mail. Normal: the parents, copies to the student, the sender,
    # the lesson's teacher (if someone else sent it) and, where wanted, the
    # class teachers; a copy to the school's own address for the archive.
    # Test: the sender alone.
    def self.envelope(test:, sender:, student:, lesson_teacher: nil, klassenleitung: [])
        if test
            {:to => [sender], :cc => [], :archive => false}
        else
            cc = [student, sender]
            cc << lesson_teacher if lesson_teacher && lesson_teacher != sender
            cc += klassenleitung
            {:to => ["eltern.#{student}"], :cc => cc.compact.uniq, :archive => true}
        end
    end

    # A test mail: »[TEST]« in the subject and a note above the text saying
    # who would get it.
    def self.mark_as_test(rendered, label, student_name)
        notice = "Testmail der Vorlage »#{label}«: Im Normalbetrieb ginge diese Mail an die Eltern von #{student_name}, " \
                 "mit Kopien an das Kind und dich. Solange die Vorlage im Zustand »Test« ist, bekommst nur du sie."
        {
            :subject => "[TEST] #{rendered[:subject]}",
            :html => "<p><em>#{CGI.escapeHTML(notice)}</em></p>\n<hr>\n#{rendered[:html]}",
        }
    end
end
