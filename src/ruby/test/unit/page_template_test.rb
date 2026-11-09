require_relative 'test_helper'
require_app 'page_template'

class PageTemplateTest < Minitest::Test
    FILES = {
        '/static/_outer.html' => "<nav>\#{nav_items}</nav>\n\#{File.read('/static/_inner.html')}",
        '/static/_inner.html' => "<p>\#{@session_user[:display_name]}</p>",
        '/static/_loop.html' => "\#{File.read('/static/_loop.html')}",
    }

    def expand(source)
        PageTemplate.expand_includes(source, read: ->(path) { FILES.fetch(path) })
    end

    def test_includes_become_part_of_the_page_source
        page = "\#{File.read('/static/_outer.html')}\n<main>\#{content}</main>"
        assert_equal "<nav>\#{nav_items}</nav>\n<p>\#{@session_user[:display_name]}</p>\n<main>\#{content}</main>",
                     expand(page)
    end

    def test_both_spellings_and_spaces
        assert_equal "<p>\#{@session_user[:display_name]}</p>", expand("\#{ File::read( '/static/_inner.html' ) }")
    end

    def test_only_sub_templates_from_static
        ["\#{File.read('/etc/passwd')}", "\#{File.read('/static/page.html')}",
         "\#{File.read('/static/_x.html' + suffix)}", "\#{#File.read('/static/_inner.html')}"].each do |source|
            assert_equal source, expand(source), 'not an include – stays an ordinary expression'
        end
    end

    def test_nesting_is_limited
        assert_raises(RuntimeError) { expand("\#{File.read('/static/_loop.html')}") }
    end

    def test_every_expression_is_evaluated_once_in_order
        codes = []
        result = PageTemplate.evaluate("a\#{x}b\#{ {k: 1}[:k] }c") { |code| codes << code; "<#{codes.size}>" }
        assert_equal ['x', ' {k: 1}[:k] '], codes
        assert_equal 'a<1>b<2>c', result
    end

    def test_source_is_not_modified
        source = "\#{x}"
        PageTemplate.evaluate(source) { 'y' }
        assert_equal "\#{x}", source
    end
end
