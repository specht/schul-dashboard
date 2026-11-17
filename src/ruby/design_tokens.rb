# Design tokens for the new design (preview): colours computed from a user's
# colour scheme (three colours, e.g. 'la2c6e80d60aea2c6e80'), for light or
# dark mode. Everything is contrast-corrected, so text stays readable with
# every scheme:
#
#   --acc, --acc-ink, --acc-soft, --acc-text   accent (buttons, current lesson)
#   --band-ink, --band-shadow                  text on the backdrop
#   --band-scrim, --band-scrim-a               soft shade behind that text
#   --subj-<code>                              fixed colour per subject
#
# Subjects sit at fixed spots on the scheme's gradient (left colour → main
# colour → right colour): languages to the left, Mathematik on the main
# colour, sciences around it, social subjects, arts and sport to the right.
module DesignTokens
    PAPER = { false => 'f3f5f8', true => '0e131a' }
    SURFACE = { false => 'ffffff', true => '161d27' }
    INK = { false => '131b26', true => 'e6ebf2' }

    # spot on the gradient (0 = left colour, 0.5 = main colour, 1 = right colour)
    # (several codes for one subject: the school's subject list uses e.g. 'Ph',
    # 'D', 'Fr', 'Ek'; all lessons need a colour, see design_tokens_test.rb)
    SUBJECT_SPOTS = {
        'de' => 0.04, 'd' => 0.04, 'en' => 0.10, 'la' => 0.16, 'frz' => 0.22, 'fr' => 0.22,
        'agr' => 0.28, 'ngr' => 0.30,
        'phy' => 0.38, 'ph' => 0.38, 'nawi' => 0.42, 'ch' => 0.46, 'ma' => 0.50, 'bio' => 0.54,
        'in' => 0.58, 'inf' => 0.58, 'itg' => 0.61,
        'gewi' => 0.66, 'ge' => 0.70, 'geo' => 0.74, 'ek' => 0.74, 'pb' => 0.78, 'pw' => 0.78,
        'eth' => 0.82, 'pl' => 0.82, 'evr' => 0.86, 'katr' => 0.86,
        'ku' => 0.90, 'ds' => 0.93, 'mu' => 0.96,
        'sp' => 1.0, 'ft' => 1.0, 'gt' => 1.0, 'rud' => 1.0, 'te' => 1.0, 'tt' => 1.0,
    }

    # codes in the subject list that are not taught subjects
    NOT_SUBJECTS = %w(ber esl fsl sl)

    # The curated set of the new design (review/2026-11/redesign.md): the
    # most used schemes and every colour family, single-coloured and colourful.
    # [colours (18 hex), name, tuned colours or nil]. Tuned colours apply only
    # to the new design's tokens; the backdrop stays the scheme's own. Other
    # schemes stay usable as people's own (and kids can make new ones).
    CURATED = [
        ['a2c6e80d60aea2c6e8', 'Sky', nil],
        ['307fdc03396cfe0e8d', 'Zoomer', nil],
        ['073b4c118ab2946b2d', 'Ravenclaw', '1d5f8a118ab2b88a3e'],
        ['053a4d001eff00d7ff', 'Unter dem Meer', nil],
        ['119c7503626414a19e', '20.000 Meilen unter dem Meer', nil],
        ['4aa03f003f2e80bc42', 'Thylakoid', '4aa03f16795a80bc42'],
        ['94b2a1ff7d03e0ff03', 'Orangensaft', nil],
        ['fcbf499e0001eeba30', 'Gryffindor', nil],
        ['6a00009626006a0000', 'Blutroter Sommer', nil],
        ['32031ba63570ff99cc', 'BOOMBAYAH', nil],
        ['7146749f6976cc8b79', 'Ice cream', '714674c0506fe0876a'],
        ['a86fd07638a15a2b7a', 'Amethyst', nil],
        ['0000ff6600ffcc00ff', 'Purple Valley', nil],
        ['788aa3e8a598b56576', 'Dreamy', nil],
        ['55beedf9b935e5185d', 'ソフトクリーム', nil],
        ['013adedf3a01f7fe2e', 'Sunset', nil],
        ['aaaaaa777777cccccc', 'Shadows', nil],
    ]
    CURATED_TUNED = CURATED.select { |_, _, tuned| tuned }.map { |key, _, tuned| [key, tuned] }.to_h

    # the scheme the new design computes its tokens from: a curated scheme's
    # tuned colours, otherwise the scheme itself
    def self.effective_scheme(color_scheme)
        code = color_scheme.to_s
        tuned = CURATED_TUNED[code[1, 18]]
        tuned ? code[0] + tuned + code[19..].to_s : code
    end

    def self.curated?(color_scheme)
        CURATED.any? { |key, _, _| key == color_scheme.to_s[1, 18] }
    end

    # the curated scheme closest to any scheme (for suggestions): compared by
    # what the new design shows – the accent and subject colours across the
    # gradient (light mode), not the raw colours, of which one may be nearly
    # white and hardly visible
    LOOK_TOKENS = %w(--acc --subj-de --subj-la --subj-ma --subj-ge --subj-sp)
    def self.look(color_scheme)
        t = tokens('l' + effective_scheme(color_scheme)[1, 18] + '0', false)
        LOOK_TOKENS.map { |k| t[k] }
    end

    def self.closest_curated(color_scheme)
        @curated_looks ||= CURATED.map { |key, _, _| look('l' + key) }
        mine = look(color_scheme)
        i = (0...CURATED.size).min_by { |j| mine.zip(@curated_looks[j]).sum { |a, b| delta_e(a, b) } }
        CURATED[i]
    end

    # 'EN' (LK), 'en' (GK), 'Nawi', 'La LK' → the key in SUBJECT_SPOTS (nil if unknown)
    def self.subject_key(code)
        key = code.to_s.strip.split(/[\s_-]/).first.to_s.downcase
        SUBJECT_SPOTS.include?(key) ? key : nil
    end

    def self.tokens(color_scheme, dark)
        dark = !!dark
        colors = [1, 7, 13].map { |i| hex_to_rgb(color_scheme.to_s[i, 6] || '000000') }
        main = colors[1]
        # a very light or grey main colour: use the most colourful of the three
        base = colourfulness(main) < 0.12 ? colors.max_by { |c| colourfulness(c) } : main
        surface = hex_to_rgb(SURFACE[dark])
        paper = hex_to_rgb(PAPER[dark])
        acc = dark ? adjust(base, surface, 5.2, :lighter) : adjust(base, [1, 1, 1], 4.6, :darker)
        tokens = {
            '--acc' => rgb_to_hex(acc),
            '--acc-ink' => dark ? '#0a1222' : '#ffffff',
            '--acc-soft' => rgb_to_hex(mix(acc, surface, dark ? 0.78 : 0.88)),
            '--acc-text' => rgb_to_hex(dark ? adjust(acc, paper, 7.0, :lighter) : adjust(acc, paper, 5.6, :darker)),
        }
        ink, scrim, alpha = band_text(colors, dark)
        tokens['--band-ink'] = ink == [1, 1, 1] ? '#ffffff' : '#131b26'
        tokens['--band-shadow'] = ink == [1, 1, 1] ? '0 1px 2px rgba(0,0,0,.25)' : 'none'
        tokens['--band-scrim'] = scrim == [0, 0, 0] ? '0,0,0' : '255,255,255'
        tokens['--band-scrim-a'] = format('%.2f', alpha)
        spread = hue_spread(colors)
        SUBJECT_SPOTS.each do |key, t|
            tokens["--subj-#{key}"] = rgb_to_hex(subject_colour(colors, t, spread, dark, surface))
        end
        tokens
    end

    # CSS for a <style> element: the tokens on :root
    def self.css(color_scheme, dark)
        ":root { " + tokens(color_scheme, dark).map { |k, v| "#{k}: #{v};" }.join(' ') + " }"
    end

    # Neighbouring subjects must be told apart, also in schemes with nearly
    # one colour: the less the scheme's hues differ, the more the hue is
    # spread along the gradient (up to ±60°), and the lightness goes up and
    # down along it (a wave with period 0.16: subjects 0.08 apart, e.g.
    # Mathematik and Informatik, get opposite tones). Readability stays the
    # floor: at least 4.5:1 for white text (light) / dark text (dark).
    LIGHTNESS_PERIOD = 0.16
    LIGHTNESS_RANGE = 5.0   # contrast added at the darkest (light mode) / lightest (dark mode) tone
    def self.subject_colour(colors, t, spread, dark, surface)
        c = gradient(colors, t)
        h, l, s = rgb_to_hls(c)
        k = [140 - spread, 0].max.clamp(0, 120)
        h = (h + (t - 0.5) * k / 360.0) % 1.0
        s = [s, 0.45].max
        c = hls_to_rgb(h, l, s)
        wave = 0.5 + 0.5 * Math.cos(2 * Math::PI * t / LIGHTNESS_PERIOD)
        dark ? fit(c, surface, 5.0 + LIGHTNESS_RANGE * wave, :lighter) : fit(c, [1, 1, 1], 4.5 + LIGHTNESS_RANGE * wave, :darker)
    end

    # like adjust, but in both directions: a colour with more contrast than
    # the target (e.g. pure blue) is brought back towards it, so the lightness
    # wave also works for very dark or saturated scheme colours. Never below
    # the target.
    def self.fit(c, bg, target, direction)
        h, l, s = rgb_to_hls(c)
        back = direction == :darker ? 0.01 : -0.01
        100.times do
            break if contrast(hex_to_rgb(rgb_to_hex(hls_to_rgb(h, l + back, s))), bg) < target + 0.4
            l += back
            break if l <= 0 || l >= 1
        end
        adjust(hls_to_rgb(h, l.clamp(0.0, 1.0), s), bg, target, direction)
    end

    # Text over the left 60 % of the backdrop band: the colour (white or ink)
    # and the weakest shade behind it that keeps 4.5:1 everywhere.
    def self.band_text(colors, dark)
        g = [colors[0], mix(colors[1], [1, 1, 1], 0.1), colors[2]]
        paper = hex_to_rgb(PAPER[dark])
        sample = lambda do |x, scrim, a|
            c = gradient(g, x)
            c = mix(c, [8 / 255.0] * 3, 0.38) if dark
            c = mix(c, scrim, x < 0.75 ? a * (1 - x / 0.75) : 0)
            mix(c, paper, 0.25)
        end
        best = nil
        [[[1, 1, 1], [0, 0, 0]], [hex_to_rgb(INK[false]), [1, 1, 1]]].each do |ink, scrim|
            (0..14).each do |i|
                a = (i * 0.05).round(2)
                if (0..12).all? { |x| contrast(ink, sample.call(x / 20.0, scrim, a)) >= 4.5 }
                    best = [ink, scrim, a] if best.nil? || a < best[2]
                    break
                end
            end
        end
        best || [[1, 1, 1], [0, 0, 0], 0.7]
    end

    # ---------- colour helpers (components 0..1) ----------
    def self.hex_to_rgb(h)
        h = h.to_s.delete('#')
        [0, 2, 4].map { |i| h[i, 2].to_i(16) / 255.0 }
    end

    def self.rgb_to_hex(c)
        '#' + c.map { |v| format('%02x', (v.clamp(0.0, 1.0) * 255).round) }.join
    end

    def self.mix(a, b, f)
        a.zip(b).map { |x, y| x + (y - x) * f }
    end

    def self.gradient(colors, t)
        k = [(t * 2).floor, 1].min
        mix(colors[k], colors[k + 1], t * 2 - k)
    end

    def self.luminance(c)
        r, g, b = c.map { |v| v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4 }
        0.2126 * r + 0.7152 * g + 0.0722 * b
    end

    def self.contrast(a, b)
        la, lb = [luminance(a), luminance(b)].sort.reverse
        (la + 0.05) / (lb + 0.05)
    end

    def self.rgb_to_hls(c)
        r, g, b = c
        mx, mn = c.max, c.min
        l = (mx + mn) / 2.0
        return [0.0, l, 0.0] if mx == mn
        d = mx - mn
        s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn)
        h = if mx == r then ((g - b) / d) % 6
            elsif mx == g then (b - r) / d + 2
            else (r - g) / d + 4
            end
        [h / 6.0, l, s]
    end

    def self.hls_to_rgb(h, l, s)
        return [l, l, l] if s == 0
        q = l < 0.5 ? l * (1 + s) : l + s - l * s
        p = 2 * l - q
        f = lambda do |t|
            t += 1 if t < 0
            t -= 1 if t > 1
            if t < 1 / 6.0 then p + (q - p) * 6 * t
            elsif t < 0.5 then q
            elsif t < 2 / 3.0 then p + (q - p) * (2 / 3.0 - t) * 6
            else p
            end
        end
        [f.call(h + 1 / 3.0), f.call(h), f.call(h - 1 / 3.0)]
    end

    def self.colourfulness(c)
        _, l, s = rgb_to_hls(c)
        s * (1 - (l - 0.5).abs * 2)
    end

    def self.hue_spread(colors)
        hues = colors.map { |c| rgb_to_hls(c)[0] * 360 }
        hues.combination(2).map { |a, b| d = (a - b).abs; [d, 360 - d].min }.max
    end

    # CIE Lab of a hex colour, and the distance of two colours (ΔE76)
    def self.lab(hex)
        r, g, b = hex_to_rgb(hex).map { |v| v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4 }
        x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
        y = r * 0.2126 + g * 0.7152 + b * 0.0722
        z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
        f = ->(v) { v > 0.008856 ? v**(1.0 / 3) : 7.787 * v + 16.0 / 116 }
        [116 * f.(y) - 16, 500 * (f.(x) - f.(y)), 200 * (f.(y) - f.(z))]
    end

    def self.delta_e(a, b)
        lab(a).zip(lab(b)).sum { |p, q| (p - q)**2 }**0.5
    end

    # distance of two schemes: their three colours, in order or mirrored
    # (the gradient direction matters little)
    def self.scheme_distance(a, b)
        ca = [1, 7, 13].map { |i| a.to_s[i, 6] }
        cb = [1, 7, 13].map { |i| b.to_s[i, 6] }
        [cb, cb.reverse].map { |c| ca.zip(c).sum { |x, y| delta_e(x, y) } }.min
    end

    # make c darker or lighter (same hue) until it reaches the contrast target on bg
    def self.adjust(c, bg, target, direction)
        h, l, s = rgb_to_hls(c)
        s = [s, 0.35].max if s < 0.25
        100.times do
            # checked as the hex colour it will be written as
            t = hex_to_rgb(rgb_to_hex(hls_to_rgb(h, l, s)))
            return t if contrast(t, bg) >= target
            l += direction == :darker ? -0.01 : 0.01
            break if l <= 0 || l >= 1
        end
        hls_to_rgb(h, l.clamp(0.0, 1.0), s)
    end
end
