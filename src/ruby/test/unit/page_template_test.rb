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

    # The security property: output (e.g. a poll title from the database) is
    # inserted as text and never evaluated, even if it contains #{...}.
    def test_output_is_never_evaluated_again
        codes = []
        result = PageTemplate.evaluate("<h1>\#{title}</h1>\#{n}") do |code|
            codes << code
            code == 'title' ? "\#{system('id')}" : '2'
        end
        assert_equal ['title', 'n'], codes
        assert_equal "<h1>\#{system('id')}</h1>2", result
    end

    def test_other_delimiters_for_mail_texts
        codes = []
        result = PageTemplate.evaluate("Termin: {row[:description]}, {name}", open: '{') do |code|
            codes << code
            code == 'name' ? '{system(1)}' : 'Samstag'
        end
        assert_equal ['row[:description]', 'name'], codes
        assert_equal 'Termin: Samstag, {system(1)}', result
    end

    def test_source_is_not_modified
        source = "\#{x}"
        PageTemplate.evaluate(source) { 'y' }
        assert_equal "\#{x}", source
    end

    def test_umlauts_around_and_inside_expressions
        codes = []
        result = PageTemplate.evaluate("Grüße \#{a{ä}} für \#{b}, Straße") do |code|
            codes << code
            code == 'b' ? 'Jörg' : 'Ü'
        end
        assert_equal ['a{ä}', 'b'], codes
        assert_equal 'Grüße Ü für Jörg, Straße', result
        assert_equal Encoding::UTF_8, result.encoding
    end

    # Large pages with umlauts (the start page has 190 KB) must not be slow:
    # counting characters from the start on every access took 200 ms there
    # and grew with the square of the size.
    def test_large_page_with_umlauts_is_fast
        source = ("<p>Größe ä ö ü \#{x}</p>\n" + "Übung " * 60) * 600
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        n = 0
        result = PageTemplate.evaluate(source) { n += 1; 'ß' }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        assert_equal 600, n
        assert_equal 600, result.scan('ß</p>').size
        assert_operator elapsed, :<, 0.25
    end
end
