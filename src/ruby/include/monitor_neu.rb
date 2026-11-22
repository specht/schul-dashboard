# New design of the hallway monitors (Flurmonitor), as an explicit opt-in per
# screen: only a monitor whose address ends in ?design=neu (light) or
# ?design=neu-dunkel (dark) shows it, e.g. /monitor/<deep link>?design=neu.
# Without the parameter monitor.html renders exactly as before, byte for byte
# (every helper below returns '' then) – for the screens, which log in with
# the monitor account. Someone whose own account has the new design switched
# on sees the new monitor too (the previews in manage_monitor); ?design=alt
# shows today's layout. The page keeps the template without the new frame.
#
# Only the monitors in the hallway: Sekretariat, Lehrerzimmer and Silentium
# keep their layout, also with the parameter.
#
# With the opt-in, monitor.html switches its own styles and script off
# (media / type attributes below) and loads preview/monitor/monitor.css and
# monitor.js, which draw the same data (the same /ws_monitor messages) in the
# new design: compact rows in columns that scroll like before, clock and the current
# lesson, tokens from the day's colour scheme, the scheme's backdrop between
# opaque boxes.
class Main < Sinatra::Base
    # value of ?design= → dark?
    MONITOR_NEU_DESIGNS = {'neu' => false, 'neu-dunkel' => true}
    MONITOR_NEU_NICHT_IM_FLUR = %w(monitor-sek monitor-lz monitor-silentium)
    MONITOR_NEU_NICHT_IM_FLUR_PFADE = %w(/monitor/sek /monitor/lz /monitor/silentium)

    def monitor_neu?
        path = ((request.path rescue '') || '').to_s
        return false unless path == '/monitor' || path.start_with?('/monitor/')
        email = (@session_user || {})[:email]
        return false if MONITOR_NEU_NICHT_IM_FLUR.any? { |x| email == "#{x}@#{SCHUL_MAIL_DOMAIN}" }
        return false if MONITOR_NEU_NICHT_IM_FLUR_PFADE.include?(path.sub(/\/\z/, ''))
        design = (params['design'] rescue nil)
        return true if design.is_a?(String) && MONITOR_NEU_DESIGNS.include?(design)
        # ?design=alt (or anything else given): today's layout
        return false unless design.nil?
        # someone who looks at the monitor with the new design switched on in
        # their account (the previews in manage_monitor, /monitor opened by
        # hand) sees the new monitor too; the screens themselves log in with
        # the monitor account, which never has it
        return false if (@session_user || {})[:is_monitor]
        ui_preview_account?
    end

    def monitor_neu_dunkel?
        return false unless monitor_neu?
        design = params['design']
        return MONITOR_NEU_DESIGNS[design] if design.is_a?(String) && MONITOR_NEU_DESIGNS.include?(design)
        # through the account's new design: its light or dark
        ui_dark?
    end

    # attribute for today's <style> in monitor.html: off with the opt-in
    def monitor_neu_alte_styles_aus
        monitor_neu? ? " media='not all'" : ''
    end

    # attribute for today's <script> in monitor.html: off with the opt-in
    def monitor_neu_altes_skript_aus
        monitor_neu? ? " type='text/plain'" : ''
    end

    # lesson times of today (the school's default grid, like the bookings
    # monitor and timetable.rb): [[stunde, start, end], …]; the school has no
    # 0. Stunde, although the grid has an index 0
    def monitor_neu_stunden
        datum = Date.today.strftime('%Y-%m-%d')
        hours_key = HOURS_FOR_KLASSE.keys.reject { |x| datum < x }.max
        return [] unless hours_key
        hours = HOURS_FOR_KLASSE[hours_key]['7a'] || HOURS_FOR_KLASSE[hours_key]['5a'] || HOURS_FOR_KLASSE[hours_key].values.first
        return [] unless hours
        hours.each_with_index.map { |(start_time, end_time), stunde| [stunde, start_time, end_time] }.reject { |x| x[0] == 0 }
    end

    # the colour scheme of the day for the new design: only the curated
    # schemes (DesignTokens::CURATED), the same all day on every screen (like
    # pick_random_color_scheme, with a generator of its own); on the days of
    # the Zeugniskonferenzen the fixed scheme of those days
    def monitor_neu_color_scheme
        return pick_random_color_scheme() if ZEUGNISKONFERENZEN.include?(Date.today.strftime('%Y-%m-%d'))
        rng = DEVELOPMENT ? Random.new : Random.new((Date.today + 1).jd)
        key = DesignTokens::CURATED[rng.rand(DesignTokens::CURATED.size)][0]
        # its own prefix (some curated schemes are dark variants): name and
        # author come from @@color_scheme_info under the full code
        own = @@color_scheme_colors.find { |c| c[0, 3].join('').delete('#') == key }
        "#{own ? own[4] : 'l'}#{key}0"
    end

    # styles, tokens, data and script of the new design (only with the opt-in)
    def monitor_neu_html(color_scheme)
        return '' unless monitor_neu?
        dark = monitor_neu_dunkel?
        backdrop, backdrop_css = design_preview_backdrop_css(color_scheme, dark)
        backdrop_url = backdrop_css[/url\(([^)]+)\)/, 1].to_s
        heute = Date.today.strftime('%Y-%m-%d')
        daten = {
            :klassen => KLASSEN_ORDER,
            :klassen_tr => KLASSEN_TR,
            :schema => @@color_scheme_info[color_scheme[0, 19]],
            :dunkel => dark,
            :heute => heute,
            :stunden => monitor_neu_stunden,
            :zeugniskonferenzen => {
                :heute => ZEUGNISKONFERENZEN[heute] || [],
                :an => get_monitor_zeugniskonferenzen()['flur'],
                :laufend => running_zeugniskonferenzen,
                :beendet => finished_zeugniskonferenzen,
            },
        }
        # inside <script>: no "</" that could end it
        json = daten.to_json.gsub('</', '<\/')
        tokens = DesignTokens.css(DesignTokens.effective_scheme(color_scheme), dark, backdrop, 1.0)
        # the head's text straight on the picture, without a shaded band, each
        # side in its own colour (title and date left, clock and lesson right)
        ink_l, shadow_l = DesignTokens.plain_band(backdrop, dark, 0.0, 0.4)
        ink_r, shadow_r = DesignTokens.plain_band(backdrop, dark, 0.65, 1.0)
        "\n<style id='monitor_neu_tokens'>#{tokens} :root { --mn-backdrop: url('#{backdrop_url.gsub(/['\\]/, '')}'); } " +
            ".mn { --mn-kopf-l: #{ink_l}; --mn-kopf-l-hof: #{shadow_l}; --mn-kopf-r: #{ink_r}; --mn-kopf-r-hof: #{shadow_r}; }</style>\n" +
            "<link href='#{preview_asset('/include/fonts-v2/fonts.css')}' rel='stylesheet' />\n" +
            "<link href='#{preview_asset('/include/tabler/tabler-icons.css')}' rel='stylesheet' />\n" +
            "<link href='#{preview_asset('/preview/monitor/monitor.css')}' rel='stylesheet' />\n" +
            "<script type='application/json' id='monitor_neu_daten'>#{json}</script>\n" +
            "<script src='#{preview_asset('/preview/monitor/monitor.js')}'></script>\n"
    end
end
