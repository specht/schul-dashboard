# Admins change the texts of the mails teachers send to parents from a
# lesson (/unterrichtsmails). Texts and rendering: lesson_mail_templates.rb;
# the mail bot (mail-bot-repl.rb) reads the stored texts before each run.

LESSON_MAIL_PREVIEW_STUDENTS = {
    'm' => {:first_name => 'Max', :name => 'Max Mustermann'},
    'w' => {:first_name => 'Erika', :name => 'Erika Mustermann'},
}

# Class teachers send mails to the parents of their class without a lesson
# (page /klassenmail/<klasse>): those mails hang at a lesson key of their own,
# '_klassenleitung_<klasse>', with one LessonInfo per day. {Fach} is
# »Klassenleitung« there.
CLASS_MAIL_KEY_PREFIX = '_klassenleitung_'
CLASS_MAIL_FACH = 'Klassenleitung'

# The Otium sends its mails for any lesson, also a Vertretung the dashboard
# cannot put into a course (no lesson count): those hang at
# '_vertretung_<klasse>' with one LessonInfo per day and lesson (see
# vertretung_mail_offset). Subject and teacher of a Vertretung come from the
# Vertretungsplan and are kept with the mail.
VERTRETUNG_KEY_PREFIX = '_vertretung_'
VERTRETUNG_FACH = 'Vertretung'

class Main < Sinatra::Base
    # the class of a class teacher's mail key, nil for a lesson key
    def self.class_mail_klasse(lesson_key)
        return nil unless lesson_key.to_s.start_with?(CLASS_MAIL_KEY_PREFIX)
        klasse = lesson_key.to_s[CLASS_MAIL_KEY_PREFIX.size..]
        @@klassen_order.include?(klasse) ? klasse : nil
    end

    def self.class_mail_key(klasse)
        "#{CLASS_MAIL_KEY_PREFIX}#{klasse}"
    end

    # the LessonInfo offset of a class teacher's mails: one per day
    def self.class_mail_offset(date = Date.today)
        (date - Date.new(2000, 1, 1)).to_i
    end

    def self.vertretung_mail_klasse(lesson_key)
        return nil unless lesson_key.to_s.start_with?(VERTRETUNG_KEY_PREFIX)
        klasse = lesson_key.to_s[VERTRETUNG_KEY_PREFIX.size..]
        @@klassen_order.include?(klasse) ? klasse : nil
    end

    # a lesson without a course: day and lesson (stunde) in one number
    def self.vertretung_mail_offset(datum, stunde)
        (Date.parse(datum.to_s) - Date.new(2000, 1, 1)).to_i * 100 + stunde.to_i
    end

    # Subject and teacher of the lesson as the Vertretungsplan has them, for
    # the student's class: {:fach (display name, only for lessons without a
    # course), :lesson_teacher (e-mail)}; empty when the lesson is as planned.
    def self.lesson_mail_context(lesson_key, sus_email, datum, stunde)
        klasse = (@@user_info[sus_email] || {})[:klasse]
        # a course: only an entry about it; no course (Vertretung): the class's
        course = @@lessons[:lesson_keys][lesson_key]
        lesson = course ? {:lehrer => course[:lehrer] || [], :fach => course[:fach]} : nil
        sub = LessonMailTemplates.substitution(@@vertretungen, datum, stunde, klasse, lesson)
        context = {}
        context[:lesson_teacher] = @@shorthands[sub[:lehrer]] if sub && sub[:lehrer]
        if vertretung_mail_klasse(lesson_key)
            fach = sub ? sub[:fach] : nil
            context[:fach] = fach ? (@@faecher[fach] || fach) : VERTRETUNG_FACH
        end
        context.compact
    end

    def klassenleitung_of?(klasse)
        teacher_logged_in? && (@@klassenleiter[klasse] || []).include?(@session_user[:shorthand])
    end

    # May the session user send a mail about this student for this key? A
    # lesson that exists (as before), or as class teacher about a student of
    # their class.
    def lesson_mail_key_allowed?(lesson_key, sus_email)
        klasse = Main.class_mail_klasse(lesson_key)
        if klasse
            klassenleitung_of?(klasse) && (@@schueler_for_klasse[klasse] || []).include?(sus_email)
        elsif (vklasse = Main.vertretung_mail_klasse(lesson_key))
            # the Otium, for a lesson without a course (Vertretung): a student
            # of that class
            user_with_role_logged_in?(:otium) && (@@schueler_for_klasse[vklasse] || []).include?(sus_email)
        else
            !@@lessons[:lesson_keys][lesson_key].nil?
        end
    end

    # the students of a class for the mail dialog on the class page
    def class_mail_students(klasse)
        (@@schueler_for_klasse[klasse] || []).map do |email|
            info = @@user_info[email] || {}
            {:email => email, :display_first_name => info[:display_first_name], :display_last_name => info[:display_last_name]}
        end.sort_by { |x| [x[:display_last_name].to_s, x[:display_first_name].to_s] }
    end

    # The teacher of a lesson (first of the lesson's teachers), nil if unknown.
    def self.lesson_mail_lesson_teacher(lesson_key)
        @@shorthands[((@@lessons[:lesson_keys][lesson_key] || {})[:lehrer] || []).first]
    end

    # Everything a lesson mail needs, for the mail bot and the teachers'
    # preview alike. The person who sends the mail signs it and gets the
    # replies – for Otium mails the teacher on Otium duty; the lesson's
    # teacher is {Lehrkraft der Stunde}.
    # datum: the lesson's day ('YYYY-MM-DD'), for {Datum}; context: from the
    # Vertretungsplan (lesson_mail_context), kept with the mail
    def self.lesson_mail_vars(sus_email, lesson_key, sender_email, details, comment = nil, datum = nil, context = {})
        context ||= {}
        sus = @@user_info[sus_email]
        lesson = @@lessons[:lesson_keys][lesson_key] || {}
        sender = @@user_info[sender_email] || {}
        lesson_teacher = @@user_info[context[:lesson_teacher]] || @@user_info[lesson_mail_lesson_teacher(lesson_key)] || sender
        {
            :first_name => sus[:display_first_name],
            :name => sus[:display_name],
            :klasse => tr_klasse(sus[:klasse]),
            :fach => context[:fach] || (class_mail_klasse(lesson_key) ? CLASS_MAIL_FACH : (lesson[:pretty_fach] || lesson[:fach])),
            :note => details,
            :comment => comment,
            :datum => datum,
            :today => Date.today,
            :teacher => sender[:display_name],
            :lesson_teacher => lesson_teacher[:display_name_official] || lesson_teacher[:display_name],
            :geschlecht => sus[:geschlecht],
        }
    end

    def stored_lesson_mail_templates
        LessonMailTemplates.from_nodes(neo4j_query("MATCH (t:LessonMailTemplate) RETURN t;").map { |row| row['t'] })
    end

    # <option>s for the timetable's mail dialog, from the reasons in the
    # database. The Otium only gets the reasons it sends (the first one
    # chosen); teachers see those greyed out. Test templates only for admins.
    def lesson_mail_options_html
        otium = user_with_role_logged_in?(:otium)
        admin = admin_logged_in?
        options = []
        options << '<option value="">Grund auswählen</option>' unless otium
        first = true
        LessonMailTemplates.catalog(stored_lesson_mail_templates).each do |x|
            next if x[:status] == 'hidden' || (x[:status] == 'test' && !admin)
            attrs = " value=\"#{CGI.escapeHTML(x[:reason])}\" data-note-hint=\"#{CGI.escapeHTML(x[:note_hint].to_s)}\""
            label = x[:label]
            if x[:status] == 'test'
                attrs += ' data-test="1"'
                label = "#{label} (Test – geht nur an dich)"
            end
            if otium
                next unless x[:sender] == 'otium'
                attrs += ' selected' if first
                first = false
            elsif x[:sender] == 'otium'
                attrs += ' disabled'
                label = "#{label} – schickt jetzt das Otium"
            end
            options << "<option#{attrs}>#{CGI.escapeHTML(label)}</option>"
        end
        options.join("\n")
    end

    # name of every reason, for lists of mails already sent
    def lesson_mail_reason_labels
        Hash[LessonMailTemplates.catalog(stored_lesson_mail_templates).map { |x| [x[:reason], x[:label]] }]
    end

    def lesson_mail_templates_page_data
        require_admin!
        stored = stored_lesson_mail_templates
        LessonMailTemplates.catalog(stored).map do |info|
            reason = info[:reason]
            entry = stored[reason]
            current = LessonMailTemplates.effective(stored, reason) || {:subject => '', :body => ''}
            default = info[:custom] ? nil : LessonMailTemplates::DEFAULTS[reason]
            {
                :reason => reason,
                :label => info[:label],
                :custom => info[:custom],
                :status => info[:status],
                :color => info[:color],
                :sender => info[:sender],
                :cc_klassenleitung => info[:cc_klassenleitung],
                :note_hint => info[:note_hint],
                :subject => current[:subject],
                :body => current[:body].strip,
                :default_subject => default ? default[:subject] : nil,
                :default_body => default ? default[:body].strip : nil,
                # the built-in texts are in the database from the start
                # (main.rb, SetupDatabase): changed means other than the default
                :customized => info[:custom] || !LessonMailTemplates.default_text?(reason, current[:subject], current[:body]),
                :updated => entry && entry[:ts_updated] ? Time.at(entry[:ts_updated].to_i).strftime('%d.%m.%Y, %H:%M') : nil,
                :updated_by => entry && entry[:updated_by] ? ((@@user_info[entry[:updated_by]] || {})[:display_name] || entry[:updated_by]) : nil,
                :example_note => info[:note_hint].to_s,
            }
        end
    end

    RULE_KEYS = [:label, :color, :status, :sender, :cc_klassenleitung, :note_hint]

    # reason '' is a new own template (preview only)
    def lesson_mail_template_request(required = [:reason, :subject, :body])
        data = parse_request_data(:required_keys => required,
                                  :optional_keys => [:reason, :note, :geschlecht] + RULE_KEYS,
                                  # true or false, checked in rule_errors
                                  :types => {:cc_klassenleitung => Object},
                                  :max_value_lengths => {:subject => LessonMailTemplates::MAX_SUBJECT_LENGTH * 2,
                                                         :body => LessonMailTemplates::MAX_BODY_LENGTH * 2,
                                                         :label => LessonMailTemplates::MAX_LABEL_LENGTH * 2,
                                                         :note_hint => LessonMailTemplates::MAX_NOTE_HINT_LENGTH * 2},
                                  :max_body_length => 32 * 1024)
        assert(data[:reason].nil? || data[:reason] == '' || LessonMailTemplates.find(stored_lesson_mail_templates, data[:reason]), 'unknown reason')
        data
    end

    def lesson_mail_rule_params(data)
        {:label => data[:label].to_s.strip, :color => data[:color].to_s.downcase, :status => data[:status],
         :sender => data[:sender], :cc_klassenleitung => data[:cc_klassenleitung], :note_hint => data[:note_hint].to_s.strip}
    end

    post '/api/preview_lesson_mail_template' do
        require_admin!
        data = lesson_mail_template_request
        geschlecht = data[:geschlecht] == 'w' ? 'w' : 'm'
        student = LESSON_MAIL_PREVIEW_STUDENTS[geschlecht]
        errors = LessonMailTemplates.template_errors(data[:subject], data[:body])
        rendered = LessonMailTemplates.render({:subject => data[:subject], :body => data[:body]}, {
            :first_name => student[:first_name],
            :name => student[:name],
            :klasse => '5a',
            :fach => 'Mathematik',
            :note => data[:note],
            :teacher => @session_user[:display_name],
            :lesson_teacher => 'Frau Beispiel',
            :geschlecht => geschlecht,
        })
        respond(:errors => errors, :subject => rendered[:subject], :html => rendered[:html])
    end

    # what a teacher (or the Otium) is about to send: the mail dialog in the
    # timetable shows it before sending
    post '/api/preview_lesson_mail' do
        assert(teacher_logged_in? || user_with_role_logged_in?(:otium))
        data = parse_request_data(:required_keys => [:email, :reason, :details, :lesson_key],
                                  :optional_keys => [:comment, :datum, :stunde],
                                  :types => {:stunde => Object},
                                  :max_value_lengths => {:details => 2048, :comment => 2048}, :max_body_length => 8192)
        stored = stored_lesson_mail_templates
        info = LessonMailTemplates.find(stored, data[:reason])
        # who sends it does not matter for a preview
        assert(info && LessonMailTemplates.sendable?(info, admin_logged_in?, true), 'unknown reason')
        assert(@@user_info[data[:email]] && !@@user_info[data[:email]][:teacher], 'unknown student')
        assert(lesson_mail_key_allowed?(data[:lesson_key], data[:email]), 'unknown lesson')
        template = LessonMailTemplates.effective(stored, data[:reason])
        rendered = LessonMailTemplates.render(template, Main.lesson_mail_vars(data[:email], data[:lesson_key], @session_user[:email], data[:details], data[:comment], data[:datum],
            Main.lesson_mail_context(data[:lesson_key], data[:email], data[:datum], data[:stunde])))
        respond(:subject => rendered[:subject], :html => rendered[:html], :text => rendered[:text])
    end

    # text and rules of a reason
    post '/api/save_lesson_mail_template' do
        require_admin!
        data = lesson_mail_template_request([:reason, :subject, :body] + RULE_KEYS)
        stored = stored_lesson_mail_templates
        info = LessonMailTemplates.find(stored, data[:reason])
        assert(info, 'unknown reason')
        errors = LessonMailTemplates.template_errors(data[:subject], data[:body]) +
                 LessonMailTemplates.rule_errors(data, stored, data[:reason], info[:custom])
        if errors.empty?
            params = lesson_mail_rule_params(data).merge({:reason => data[:reason], :subject => data[:subject].strip,
                :body => data[:body].gsub(/\r\n?/, "\n").strip, :ts => Time.now.to_i, :email => @session_user[:email]})
            neo4j_query_expect_one(<<~END_OF_QUERY, params)
                MERGE (t:LessonMailTemplate {reason: $reason})
                SET t.subject = $subject, t.body = $body, t.label = $label, t.color = $color, t.status = $status,
                    t.sender = $sender, t.cc_klassenleitung = $cc_klassenleitung, t.note_hint = $note_hint,
                    t.ts_updated = $ts, t.updated_by = $email
                RETURN t;
            END_OF_QUERY
            debug "Lesson mail template changed: #{data[:reason]}"
            respond(:templates => lesson_mail_templates_page_data)
        else
            # not saved; api_call sets success itself
            respond(:errors => errors)
        end
    end

    # a new own template, in the state 'test'
    post '/api/create_lesson_mail_template' do
        require_admin!
        data = lesson_mail_template_request([:subject, :body] + RULE_KEYS - [:status])
        data[:status] = 'test'
        stored = stored_lesson_mail_templates
        errors = LessonMailTemplates.rule_errors(data, stored, nil, true) + LessonMailTemplates.template_errors(data[:subject], data[:body])
        if errors.empty?
            reason = LessonMailTemplates::CUSTOM_PREFIX + RandomTag.generate(8)
            ts = Time.now.to_i
            params = lesson_mail_rule_params(data).merge({:reason => reason, :subject => data[:subject].strip,
                :body => data[:body].gsub(/\r\n?/, "\n").strip, :ts => ts, :email => @session_user[:email]})
            neo4j_query_expect_one(<<~END_OF_QUERY, params)
                CREATE (t:LessonMailTemplate {reason: $reason, custom: true})
                SET t.subject = $subject, t.body = $body, t.label = $label, t.color = $color, t.status = $status,
                    t.sender = $sender, t.cc_klassenleitung = $cc_klassenleitung, t.note_hint = $note_hint,
                    t.ts_created = $ts, t.ts_updated = $ts, t.updated_by = $email
                RETURN t;
            END_OF_QUERY
            debug "Lesson mail template created: #{reason}"
            respond(:reason => reason, :templates => lesson_mail_templates_page_data)
        else
            respond(:errors => errors)
        end
    end

    # the built-in default text again (rules stay as they are)
    post '/api/reset_lesson_mail_template' do
        require_admin!
        data = parse_request_data(:required_keys => [:reason])
        # own templates have no default text
        assert(LessonMailTemplates::REASONS.include?(data[:reason]), 'unknown reason')
        default = LessonMailTemplates::DEFAULTS[data[:reason]]
        neo4j_query(<<~END_OF_QUERY, {:reason => data[:reason], :subject => default[:subject], :body => default[:body].strip, :ts => Time.now.to_i, :email => @session_user[:email]})
            MERGE (t:LessonMailTemplate {reason: $reason})
            SET t.subject = $subject, t.body = $body, t.ts_updated = $ts, t.updated_by = $email;
        END_OF_QUERY
        debug "Lesson mail text reset: #{data[:reason]}"
        respond(:templates => lesson_mail_templates_page_data)
    end
end
