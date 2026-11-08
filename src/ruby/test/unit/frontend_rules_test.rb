require_relative 'test_helper'

# Static checks for rules from AGENTS.md that are easy to break unnoticed.
class FrontendRulesTest < Minitest::Test
    STATIC_DIR = File.expand_path('../../../static', __dir__)

    # our own pages and scripts, not the third-party libraries in include/
    def own_frontend_files
        Dir[File.join(STATIC_DIR, '**', '*.{html,js}')].reject do |path|
            path.include?('/include/')
        end
    end

    def test_no_native_browser_dialogs
        offenders = []
        own_frontend_files.each do |path|
            File.readlines(path, encoding: 'utf-8').each_with_index do |line, i|
                next if line.strip.start_with?('//', '*', '#')
                if line =~ /(?<![\w.$])(window\.)?(alert|confirm|prompt)\(/
                    offenders << "#{path.sub(STATIC_DIR + '/', '')}:#{i + 1}: #{line.strip[0, 80]}"
                end
            end
        end
        assert_empty offenders, "Use dashboardAlert()/dashboardConfirm() instead of native dialogs:\n" + offenders.join("\n")
    end
end
