require_relative 'test_helper'

# Static checks for rules from AGENTS.md that are easy to break unnoticed.
class BackendRulesTest < Minitest::Test
    RUBY_DIR = File.expand_path('../..', __dir__)

    def own_ruby_files
        Dir[File.join(RUBY_DIR, '**', '*.rb')].reject do |path|
            path.include?('/test/') || File.basename(path).start_with?('credentials')
        end
    end

    # Mails must go through deliver_with_development_guard! (main.rb), so that
    # a development instance with real data can only mail the positive list.
    def test_mail_is_only_sent_through_the_development_guard
        offenders = []
        own_ruby_files.each do |path|
            File.readlines(path, encoding: 'utf-8').each_with_index do |line, i|
                next if line.strip.start_with?('#')
                next unless line =~ /\.deliver!?(\s|\(|$)/
                offenders << "#{path.sub(RUBY_DIR + '/', '')}:#{i + 1}: #{line.strip}"
            end
        end
        assert_equal ['main.rb'], offenders.map { |o| o.split(':').first }.uniq,
                     "Send mail via deliver_with_development_guard!(mail):\n" + offenders.join("\n")
        assert_equal 1, offenders.size, offenders.join("\n")
    end

    # Neo4j 5 no longer knows exists(n.prop) – a syntax error there; the
    # replacement works on 4.4 as well. (exists() with a pattern is fine.)
    def test_no_exists_function_on_properties
        offenders = []
        own_ruby_files.each do |path|
            File.readlines(path, encoding: 'utf-8').each_with_index do |line, i|
                next if line.strip.start_with?('#')
                next unless line =~ /\bexists\s*\(\s*\w+\.\w+\s*\)/i
                offenders << "#{path.sub(RUBY_DIR + '/', '')}:#{i + 1}: #{line.strip}"
            end
        end
        assert_empty offenders, "Use n.prop IS NOT NULL / IS NULL instead of EXISTS(n.prop):\n" + offenders.join("\n")
    end

    # Login and confirmation codes must come from SecureRandom. rand/srand use
    # Ruby's global generator, which other code seeds with fixed or guessable
    # values – shared by all request threads.
    def test_codes_only_from_secure_random
        offenders = []
        %w(include/login.rb include/otp.rb include/sms.rb).each do |file|
            File.readlines(File.join(RUBY_DIR, file), encoding: 'utf-8').each_with_index do |line, i|
                next if line.strip.start_with?('#')
                next unless line =~ /(?<![\w.:])s?rand\s*\(|Random\.new/
                offenders << "#{file}:#{i + 1}: #{line.strip}"
            end
        end
        assert_empty offenders, "Use RandomTag::digits / SecureRandom for codes:\n" + offenders.join("\n")
    end

    # No shell strings with values in them (AGENTS.md): system('cmd', arg, …).
    # Known exceptions build their commands only from random tags, the
    # school's own configuration or the repository – not from requests or
    # uploads. Don't add to this list; convert instead.
    SHELL_STRING_EXCEPTIONS = {
        'include/comment.rb' => 1,  # ffmpeg, paths from a random tag
        'include/zeugnisse.rb' => 1, # unzip of the configured forms
        'main.rb' => 2,              # advent calendar, names from a tracked file
    }

    def test_no_new_shell_strings_with_values
        found = Hash.new(0)
        lines = []
        files = Dir[File.join(RUBY_DIR, 'main.rb')] + Dir[File.join(RUBY_DIR, 'include', '**', '*.rb')] +
                Dir[File.join(RUBY_DIR, '*-repl.rb')]
        files.each do |path|
            File.readlines(path, encoding: 'utf-8').each_with_index do |line, i|
                next if line.strip.start_with?('#')
                next unless (line =~ /\b(system|spawn|exec|popen\w*|capture\w*)\s*\(?\s*"/ && line.include?('#{')) ||
                            line =~ /`[^`]*#\{/ || line =~ /%x[\(\{\[]/
                file = path.sub(RUBY_DIR + '/', '')
                found[file] += 1
                lines << "#{file}:#{i + 1}: #{line.strip}"
            end
        end
        assert_equal SHELL_STRING_EXCEPTIONS, found.to_h,
                     "Call programs with an argument list instead of a shell string:\n" + lines.join("\n")
    end
end
