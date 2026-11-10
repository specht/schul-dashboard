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
end
