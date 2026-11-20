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

    # A block left open (a missing "}" after an @media) silently moves every
    # rule below it into that block – e.g. desktop styles that only apply on
    # phones. Our own stylesheets (not include/) must close what they open.
    def test_stylesheets_close_every_block
        offenders = []
        Dir[File.join(STATIC_DIR, '**', '*.css')].reject { |path| path.include?('/include/') }.each do |path|
            # comments and strings may hold braces
            text = File.read(path, encoding: 'utf-8')
            text = text.gsub(%r{/\*.*?\*/}m, '').gsub(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/, '""')
            depth = 0
            text.each_char do |c|
                depth += 1 if c == '{'
                depth -= 1 if c == '}'
                break if depth < 0
            end
            next if depth == 0
            offenders << "#{path.sub(STATIC_DIR + '/', '')}: " + (depth > 0 ? "#{depth} block(s) not closed" : 'a "}" without "{"')
        end
        assert_empty offenders, "Unbalanced braces in stylesheets:\n" + offenders.join("\n")
    end
end
