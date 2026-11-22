require_relative 'test_helper'

# Every Ruby file of the app compiles: a syntax error in an include stops the
# web service at startup, and most includes aren't loaded by other unit tests.
class RubySyntaxTest < Minitest::Test
    def test_all_files_compile
        files = Dir[File.join(APP_ROOT, '*.rb')] + Dir[File.join(APP_ROOT, 'include', '*.rb')]
        refute_empty files
        broken = files.filter_map do |path|
            begin
                RubyVM::InstructionSequence.compile(File.read(path), path)
                nil
            rescue SyntaxError => e
                "#{File.basename(path)}: #{e.message.lines.first.strip}"
            end
        end
        assert_empty broken
    end
end
