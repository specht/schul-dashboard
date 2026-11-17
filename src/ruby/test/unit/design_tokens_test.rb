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

    # neighbours on the gradient that are often taught by the same person can
    # be told apart in most schemes (colour distance ΔE76, median over schemes)
    def test_neighbouring_subjects_differ
        lab = lambda do |hex|
            r, g, b = T.hex_to_rgb(hex).map { |v| v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4 }
            x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
            y = r * 0.2126 + g * 0.7152 + b * 0.0722
            z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
            f = ->(v) { v > 0.008856 ? v**(1.0 / 3) : 7.787 * v + 16.0 / 116 }
            [116 * f.(y) - 16, 500 * (f.(x) - f.(y)), 200 * (f.(y) - f.(z))]
        end
        [%w(ma in), %w(ma bio), %w(ma ph), %w(ge pw), %w(en la)].each do |a, b|
            [false, true].each do |dark|
                d = COLOR_SCHEME_COLORS.map do |entry|
                    t = T.tokens(entry[0], dark)
                    lab.(t["--subj-#{a}"]).zip(lab.(t["--subj-#{b}"])).sum { |p, q| (p - q)**2 }**0.5
                end.sort
                assert_operator d[d.size / 2], :>=, 15, "#{a}/#{b} #{dark ? 'dunkel' : 'hell'}: Median #{d[d.size / 2].round}"
            end
        end
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
