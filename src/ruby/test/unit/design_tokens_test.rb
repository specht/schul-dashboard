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
        [%w(ma in), %w(ma bio), %w(ma ph), %w(ge pw), %w(en la)].each do |a, b|
            [false, true].each do |dark|
                d = COLOR_SCHEME_COLORS.map do |entry|
                    t = T.tokens(entry[0], dark)
                    T.delta_e(t["--subj-#{a}"], t["--subj-#{b}"])
                end.sort
                assert_operator d[d.size / 2], :>=, 15, "#{a}/#{b} #{dark ? 'dunkel' : 'hell'}: Median #{d[d.size / 2].round}"
            end
        end
    end

    # the curated set: real schemes, tuned colours only for themselves and
    # readable like all others
    def test_curated_set
        keys = COLOR_SCHEME_COLORS.map { |entry| entry[0][1, 18] }
        T::CURATED.each { |key, name, _| assert_includes keys, key, name }
        assert_operator T::CURATED.size, :>=, 12
        assert T.curated?('la2c6e80d60aea2c6e80')
        assert_equal 'la2c6e80d60aea2c6e80', T.effective_scheme('la2c6e80d60aea2c6e80')
        assert_equal 'd4aa03f16795a80bc423', T.effective_scheme('d4aa03f003f2e80bc423')
        assert_equal 'Sky', T.closest_curated('la2c6e80d60aea2c6e80')[1]
        T::CURATED_TUNED.each_value do |tuned|
            [false, true].each do |dark|
                t = T.tokens('l' + tuned + '0', dark)
                surface = rgb(T::SURFACE[dark])
                T::SUBJECT_SPOTS.each_key do |key|
                    assert_operator T.contrast(rgb(t["--subj-#{key}"]), surface), :>=, 4.5, "#{tuned} #{dark}: #{key}"
                end
                assert_operator T.contrast(rgb(t['--acc']), surface), :>=, 4.5
            end
        end
    end

    def test_scheme_distance
        sky = 'la2c6e80d60aea2c6e80'
        assert_in_delta 0, T.scheme_distance(sky, sky), 0.001
        # mirrored counts as the same scheme
        assert_in_delta 0, T.scheme_distance('l55beedf9b935e5185d0', 'le5185df9b93555beed0'), 0.001
        assert_operator T.scheme_distance(sky, 'l55beedf9b935e5185d0'), :>, 50
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
