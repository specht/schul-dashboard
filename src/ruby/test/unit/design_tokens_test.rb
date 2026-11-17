require_relative 'test_helper'
require_app 'design_tokens'
require_app 'include/color-schemes'

# The new design computes its colours from the user's colour scheme. Whatever
# scheme someone picked, text has to stay readable – in light and dark mode.
class DesignTokensTest < Minitest::Test
    T = DesignTokens

    def each_scheme
        COLOR_SCHEME_COLORS.each do |entry|
            [false, true].each { |dark| yield entry[0], entry[1], dark }
        end
    end

    def rgb(hex) = T.hex_to_rgb(hex)

    def test_accent_is_readable_in_every_scheme
        each_scheme do |code, name, dark|
            t = T.tokens(code, dark)
            surface = rgb(T::SURFACE[dark])
            paper = rgb(T::PAPER[dark])
            assert_operator T.contrast(rgb(t['--acc']), surface), :>=, 4.5, "#{name} #{dark ? 'dunkel' : 'hell'}: Akzent"
            assert_operator T.contrast(rgb(t['--acc-text']), paper), :>=, 4.5, "#{name}: Akzent als Text"
            assert_operator T.contrast(rgb(t['--acc-ink']), rgb(t['--acc'])), :>=, 3.0, "#{name}: Schrift auf dem Akzent"
        end
    end

    # every subject of the subject list (example data, mounted at /data) has a
    # colour – a lesson without one looks like a cancelled one
    def test_every_subject_has_a_colour
        codes = File.readlines('/data/faecher/faecher.csv').drop(1).map { |l| l.split(',').first.to_s.strip }.reject(&:empty?)
        assert_operator codes.size, :>, 30
        missing = codes.reject { |c| T.subject_key(c) || T::NOT_SUBJECTS.include?(c.downcase) }
        assert_equal [], missing
    end

    def test_subject_colours_are_readable_in_every_scheme
        each_scheme do |code, name, dark|
            t = T.tokens(code, dark)
            surface = rgb(T::SURFACE[dark])
            T::SUBJECT_SPOTS.each_key do |key|
                assert_operator T.contrast(rgb(t["--subj-#{key}"]), surface), :>=, 4.5, "#{name} #{dark}: #{key}"
            end
        end
    end

    def test_text_on_the_backdrop_is_readable_in_every_scheme
        each_scheme do |code, name, dark|
            colors = [1, 7, 13].map { |i| rgb(code[i, 6]) }
            ink, _scrim, alpha = T.band_text(colors, dark)
            assert_operator alpha, :<=, 0.7, "#{name}: Schatten"
            assert_includes [[1, 1, 1], rgb(T::INK[false])], ink
        end
    end

    # Mathematik sits on the scheme's main colour; languages and arts at the ends
    def test_subjects_follow_the_gradient
        assert_equal 0.5, T::SUBJECT_SPOTS['ma']
        assert_operator T::SUBJECT_SPOTS['de'], :<, T::SUBJECT_SPOTS['nawi']
        assert_operator T::SUBJECT_SPOTS['gewi'], :<, T::SUBJECT_SPOTS['ku']
        sky = T.tokens('la2c6e80d60aea2c6e80', false)
        # a nearly one-coloured scheme still gives subjects different colours
        assert_operator sky.select { |k, _| k.start_with?('--subj-') }.values.uniq.size, :>=, 15
    end

    def test_subject_codes_from_the_timetable
        assert_equal 'en', T.subject_key('EN')
        assert_equal 'en', T.subject_key('en')
        assert_equal 'nawi', T.subject_key('Nawi')
        assert_equal 'la', T.subject_key('La LK')
        assert_equal 'ma', T.subject_key('ma_11')
        assert_nil T.subject_key('Verteidigung gegen die dunklen Künste')
    end

    def test_css_is_one_rule_on_root
        css = T.css('la2c6e80d60aea2c6e80', true)
        assert css.start_with?(':root {')
        assert_includes css, '--acc: #'
        refute_includes css, '#{'
    end
end
