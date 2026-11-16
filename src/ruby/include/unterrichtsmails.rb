# Admins change the texts of the mails teachers send to parents from a
# lesson (/unterrichtsmails). Texts and rendering: lesson_mail_templates.rb;
# the mail bot (mail-bot-repl.rb) reads the stored texts before each run.

LESSON_MAIL_PREVIEW_STUDENTS = {
    'm' => {:first_name => 'Max', :name => 'Max Mustermann'},
    'w' => {:first_name => 'Erika', :name => 'Erika Mustermann'},
}

class Main < Sinatra::Base
    # The teacher of a lesson (first of the lesson's teachers), nil if unknown.
    def self.lesson_mail_lesson_teacher(lesson_key)
        @@shorthands[((@@lessons[:lesson_keys][lesson_key] || {})[:lehrer] || []).first]
    end

    # Everything a lesson mail needs, for the mail bot and the teachers'
    # preview alike. The person who sends the mail signs it and gets the
    # replies – for Otium mails the teacher on Otium duty; the lesson's
    # teacher is {Lehrkraft der Stunde}.
    def self.lesson_mail_vars(sus_email, lesson_key, sender_email, details)
        sus = @@user_info[sus_email]
        lesson = @@lessons[:lesson_keys][lesson_key] || {}
        sender = @@user_info[sender_email] || {}
        lesson_teacher = @@user_info[lesson_mail_lesson_teacher(lesson_key)] || sender
        {
            :first_name => sus[:display_first_name],
            :name => sus[:display_name],
            :klasse => tr_klasse(sus[:klasse]),
            :fach => lesson[:pretty_fach] || lesson[:fach],
            :note => details,
            :teacher => sender[:display_name],
            :lesson_teacher => lesson_teacher[:display_name_official] || lesson_teacher[:display_name],
            :geschlecht => sus[:geschlecht],
        }
    end

    def stored_lesson_mail_templates
        result = {}
        neo4j_query("MATCH (t:LessonMailTemplate) RETURN t;").each do |row|
            t = row['t']
            result[t[:reason]] = {:subject => t[:subject], :body => t[:body],
                                  :ts_updated => t[:ts_updated], :updated_by => t[:updated_by]}
        end
        result
    end

    def lesson_mail_templates_page_data
        require_admin!
        stored = stored_lesson_mail_templates
        LessonMailTemplates::REASONS.map do |reason|
            entry = stored[reason]
            current = LessonMailTemplates.effective(stored, reason)
            {
                :reason => reason,
                :label => LessonMailTemplates::LABELS[reason],
                :subject => current[:subject],
                :body => current[:body].strip,
                :default_subject => LessonMailTemplates::DEFAULTS[reason][:subject],
                :default_body => LessonMailTemplates::DEFAULTS[reason][:body].strip,
                :customized => !entry.nil?,
                :updated => entry ? Time.at(entry[:ts_updated].to_i).strftime('%d.%m.%Y, %H:%M') : nil,
                :updated_by => entry ? ((@@user_info[entry[:updated_by]] || {})[:display_name] || entry[:updated_by]) : nil,
                :example_note => LessonMailTemplates::EXAMPLE_NOTES[reason] || '',
            }
        end
    end

    def lesson_mail_template_request
        data = parse_request_data(:required_keys => [:reason, :subject, :body], :optional_keys => [:note, :geschlecht],
                                  :max_value_lengths => {:subject => LessonMailTemplates::MAX_SUBJECT_LENGTH * 2,
                                                         :body => LessonMailTemplates::MAX_BODY_LENGTH * 2},
                                  :max_body_length => 32 * 1024)
        assert(LessonMailTemplates::REASONS.include?(data[:reason]), 'unknown reason')
        data
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
                                  :max_value_lengths => {:details => 2048}, :max_body_length => 4096)
        assert(LessonMailTemplates::REASONS.include?(data[:reason]), 'unknown reason')
        assert(@@user_info[data[:email]] && !@@user_info[data[:email]][:teacher], 'unknown student')
        assert(@@lessons[:lesson_keys][data[:lesson_key]], 'unknown lesson')
        template = LessonMailTemplates.effective(stored_lesson_mail_templates, data[:reason])
        rendered = LessonMailTemplates.render(template, Main.lesson_mail_vars(data[:email], data[:lesson_key], @session_user[:email], data[:details]))
        respond(:subject => rendered[:subject], :html => rendered[:html])
    end

    post '/api/save_lesson_mail_template' do
        require_admin!
        data = lesson_mail_template_request
        errors = LessonMailTemplates.template_errors(data[:subject], data[:body])
        if errors.empty?
            subject = data[:subject].strip
            body = data[:body].gsub(/\r\n?/, "\n").strip
            default = LessonMailTemplates::DEFAULTS[data[:reason]]
            if subject == default[:subject] && body == default[:body].strip
                # the default text again: nothing to keep, later changes to the
                # default apply again
                neo4j_query("MATCH (t:LessonMailTemplate {reason: $reason}) DETACH DELETE t;", {:reason => data[:reason]})
            else
                neo4j_query(<<~END_OF_QUERY, {:reason => data[:reason], :subject => subject, :body => body, :ts => Time.now.to_i, :email => @session_user[:email]})
                    MERGE (t:LessonMailTemplate {reason: $reason})
                    SET t.subject = $subject, t.body = $body, t.ts_updated = $ts, t.updated_by = $email;
                END_OF_QUERY
            end
            debug "Lesson mail text changed: #{data[:reason]}"
            respond(:templates => lesson_mail_templates_page_data)
        else
            # not saved; api_call sets success itself
            respond(:errors => errors)
        end
    end

    post '/api/reset_lesson_mail_template' do
        require_admin!
        data = parse_request_data(:required_keys => [:reason])
        assert(LessonMailTemplates::REASONS.include?(data[:reason]), 'unknown reason')
        neo4j_query("MATCH (t:LessonMailTemplate {reason: $reason}) DETACH DELETE t;", {:reason => data[:reason]})
        debug "Lesson mail text reset: #{data[:reason]}"
        respond(:templates => lesson_mail_templates_page_data)
    end
end
