require_relative 'test_helper'
require_app 'monitor_effekte'

class MonitorEffekteTest < Minitest::Test
    JETZT = Time.at(1_800_000_000)
    MS = 1_800_000_000_000

    def warnung(event, level, start: MS - 3_600_000, ende: MS + 3_600_000)
        {'event' => event, 'level' => level, 'start' => start, 'end' => ende, 'type' => 0}
    end

    def daten(*warnungen)
        {'warnings' => {'111000000' => warnungen, '106535000' => [warnung('STARKER SCHNEEFALL', 4)]}}
    end

    def test_reads_the_jsonp_answer_of_the_dwd
        text = 'warnWetter.loadWarnings({"time":1,"warnings":{"111000000":[{"event":"WINDBÖEN","level":2}]},"vorabInformation":{}});'
        d = MonitorEffekte.parse_dwd(text.b)
        assert_equal 'WINDBÖEN', d['warnings']['111000000'][0]['event']
        assert_nil MonitorEffekte.parse_dwd('Wartungsarbeiten')
        assert_nil MonitorEffekte.parse_dwd(nil)
    end

    def test_only_strong_weather_gets_an_effect
        assert_nil MonitorEffekte.wetter(daten(warnung('SCHNEEFALL', 2)), '111000000', JETZT)
        assert_nil MonitorEffekte.wetter(daten(warnung('GEWITTER', 2)), '111000000', JETZT)
        assert_nil MonitorEffekte.wetter(daten(warnung('STURMBÖEN', 3)), '111000000', JETZT)
        assert_nil MonitorEffekte.wetter(daten(warnung('SCHWERE STURMBÖEN', 3)), '111000000', JETZT)
        assert_nil MonitorEffekte.wetter(daten(warnung('DICHTER NEBEL', 3)), '111000000', JETZT)
        assert_nil MonitorEffekte.wetter(daten(warnung('STARKES TAUWETTER', 3)), '111000000', JETZT)
        assert_equal 'schnee', MonitorEffekte.wetter(daten(warnung('STARKER SCHNEEFALL', 3)), '111000000', JETZT)[:effekt]
        assert_equal 'regen', MonitorEffekte.wetter(daten(warnung('STARKREGEN', 3)), '111000000', JETZT)[:effekt]
        assert_equal 'gewitter', MonitorEffekte.wetter(daten(warnung('STARKES GEWITTER', 3)), '111000000', JETZT)[:effekt]
        assert_equal 'sturm', MonitorEffekte.wetter(daten(warnung('ORKANARTIGE BÖEN', 4)), '111000000', JETZT)[:effekt]
        assert_equal 'frost', MonitorEffekte.wetter(daten(warnung('GLATTEIS', 4)), '111000000', JETZT)[:effekt]
        assert_equal 'hitze', MonitorEffekte.wetter(daten(warnung('STARKE HITZE', 10)), '111000000', JETZT)[:effekt]
    end

    def test_strength_follows_the_warning_level
        assert_equal 1, MonitorEffekte.wetter(daten(warnung('STARKER SCHNEEFALL', 3)), '111000000', JETZT)[:staerke]
        assert_equal 2, MonitorEffekte.wetter(daten(warnung('EXTREM STARKER SCHNEEFALL', 4)), '111000000', JETZT)[:staerke]
        assert_equal 3, MonitorEffekte.wetter(daten(warnung('EXTREM STARKER SCHNEEFALL', 5)), '111000000', JETZT)[:staerke]
        assert_equal 2, MonitorEffekte.wetter(daten(warnung('STARKE HITZE', 10)), '111000000', JETZT)[:staerke]
        assert_equal 3, MonitorEffekte.wetter(daten(warnung('EXTREME HITZE', 11)), '111000000', JETZT)[:staerke]
    end

    def test_only_warnings_of_the_own_cell_that_apply_now
        assert_nil MonitorEffekte.wetter(daten, '111000000', JETZT)
        assert_nil MonitorEffekte.wetter(daten, '999999999', JETZT)
        spaeter = warnung('STARKER SCHNEEFALL', 3, start: MS + 60_000)
        vorbei = warnung('STARKER SCHNEEFALL', 3, ende: MS)
        assert_nil MonitorEffekte.wetter(daten(spaeter, vorbei), '111000000', JETZT)
        assert_nil MonitorEffekte.wetter(nil, '111000000', JETZT)
    end

    def test_thunderstorm_wins_and_title_and_end_are_given
        w = MonitorEffekte.wetter(daten(warnung('STARKREGEN', 3), warnung('SCHWERES GEWITTER mit HEFTIGEM STARKREGEN', 4)), '111000000', JETZT)
        assert_equal 'gewitter', w[:effekt]
        assert_equal 'Schweres Gewitter mit heftigem Starkregen', w[:titel]
        assert_equal MS + 3_600_000, w[:bis]
        assert_equal 'Orkanartige Böen', MonitorEffekte.titel('ORKANARTIGE BÖEN')
    end

    def test_settings_switch_effects_off_and_move_the_threshold
        regeln = MonitorEffekte.regeln('schnee' => {:an => false}, 'regen' => {:ab => 2}, 'sturm' => {:ab => 3},
                                       'hitze' => {:ab => 11}, 'frost' => {:ab => 99})
        assert_nil MonitorEffekte.wetter(daten(warnung('STARKER SCHNEEFALL', 4)), '111000000', JETZT, regeln)
        assert_equal 'regen', MonitorEffekte.wetter(daten(warnung('DAUERREGEN', 2)), '111000000', JETZT, regeln)[:effekt]
        assert_equal 'sturm', MonitorEffekte.wetter(daten(warnung('STURMBÖEN', 3)), '111000000', JETZT, regeln)[:effekt]
        assert_nil MonitorEffekte.wetter(daten(warnung('STARKE HITZE', 10)), '111000000', JETZT, regeln)
        assert_equal 'hitze', MonitorEffekte.wetter(daten(warnung('EXTREME HITZE', 11)), '111000000', JETZT, regeln)[:effekt]
        # unbekannte Stufe → Standard (orange)
        assert_equal 3, regeln['frost'][:ab]
        assert_equal({:an => true, :ab => 3}, MonitorEffekte.regeln({})['schnee'])
    end

    def test_warning_list_for_the_admin_page
        liste = MonitorEffekte.warnungen(daten(warnung('WINDBÖEN', 2), warnung('STARKER SCHNEEFALL', 3, start: MS + 3_600_000)), '111000000', JETZT)
        assert_equal ['Windböen', 'Starker Schneefall'], liste.map { |w| w[:titel] }
        assert_equal [nil, 'schnee'], liste.map { |w| w[:effekt] }
        assert_equal ['sturm', 'schnee'], liste.map { |w| w[:art] }
        assert_equal [true, false], liste.map { |w| w[:gilt_jetzt] }
        assert_equal 'Wetterwarnung (gelb)', liste[0][:stufe_text]
    end

    def test_zeus_comes_with_every_thunderstorm
        (0...20).each do |i|
            w = warnung('STARKES GEWITTER', 3, start: MS - i * 60_000)
            assert_equal true, MonitorEffekte.wetter(daten(w), '111000000', JETZT)[:zeus]
        end
        assert_nil MonitorEffekte.wetter(daten(warnung('STARKER SCHNEEFALL', 3)), '111000000', JETZT)[:zeus]
    end

    def test_easter_bunny_starts_a_week_before_the_easter_holidays
        # Berlin 2027: Osterferien 22.3.–2.4., Ostersonntag 28.3.
        ferien = [{:from => '2027-03-22', :to => '2027-04-02', :title => 'Osterferien'},
                  {:from => '2027-02-01', :to => '2027-02-06', :title => 'Winterferien'}]
        assert_nil MonitorEffekte.fest(Date.new(2027, 3, 14), ferien)
        assert_equal 'ostern', MonitorEffekte.fest(Date.new(2027, 3, 15), ferien)[:fest]
        assert_equal 'ostern', MonitorEffekte.fest(Date.new(2027, 3, 29), ferien)[:fest]
        assert_nil MonitorEffekte.fest(Date.new(2027, 3, 30), ferien)
        assert_equal Date.new(2027, 3, 22), MonitorEffekte.osterferien_beginn(Date.new(2027, 3, 28), ferien)
        assert_nil MonitorEffekte.osterferien_beginn(Date.new(2027, 3, 28), [])
    end

    def test_valentine_carnival_and_last_school_day
        assert_equal 'valentinstag', MonitorEffekte.fest(Date.new(2027, 2, 14))[:fest]
        # Ostern 2027: 28.3. → Rosenmontag 8.2., Faschingsdienstag 9.2.
        assert_equal 'fasching', MonitorEffekte.fest(Date.new(2027, 2, 8))[:fest]
        assert_equal 'fasching', MonitorEffekte.fest(Date.new(2027, 2, 9))[:fest]
        assert_nil MonitorEffekte.fest(Date.new(2027, 2, 10))
        # Sommerferien beginnen an einem Donnerstag; der Mittwoch davor ist Feiertag
        ferien = [{:from => '2027-07-08', :to => '2027-08-20', :title => 'Sommerferien'},
                  {:from => '2027-07-07', :to => '2027-07-07', :title => 'Unterrichtsfrei'}]
        assert_equal Date.new(2027, 7, 6), MonitorEffekte.letzter_schultag_vor_sommerferien(2027, ferien)
        assert_equal 'sommerferien', MonitorEffekte.fest(Date.new(2027, 7, 6), ferien)[:fest]
        assert_nil MonitorEffekte.fest(Date.new(2027, 7, 5), ferien)
        assert_nil MonitorEffekte.letzter_schultag_vor_sommerferien(2027, [])
    end

    def test_single_days_beat_the_weather_feast_periods_give_way
        sturm = {:effekt => 'sturm', :staerke => 2, :titel => 'Orkanböen', :bis => nil}
        assert_equal [nil, {:fest => 'valentinstag', :nah => true}, 'wetter'],
                     MonitorEffekte.vorrang(sturm, {:fest => 'valentinstag', :nah => true})
        assert_equal [nil, {:fest => 'fasching', :nah => true}, 'wetter'],
                     MonitorEffekte.vorrang(sturm, {:fest => 'fasching', :nah => true})
        assert_equal [nil, {:fest => 'sommerferien', :nah => true}, 'wetter'],
                     MonitorEffekte.vorrang(sturm, {:fest => 'sommerferien', :nah => true})
        assert_equal [sturm, nil, 'fest'], MonitorEffekte.vorrang(sturm, {:fest => 'weihnachten', :nah => true})
        assert_equal [sturm, nil, 'fest'], MonitorEffekte.vorrang(sturm, {:fest => 'ostern', :nah => false})
        assert_equal [sturm, nil, nil], MonitorEffekte.vorrang(sturm, nil)
        assert_equal [nil, {:fest => 'ostern', :nah => true}, nil], MonitorEffekte.vorrang(nil, {:fest => 'ostern', :nah => true})
        assert_equal [nil, nil, nil], MonitorEffekte.vorrang(nil, nil)
    end

    def test_nikolaus_moves_to_the_nearest_school_day
        assert_equal Date.new(2027, 12, 6), MonitorEffekte.nikolaustag(2027)   # Montag
        assert_equal Date.new(2025, 12, 5), MonitorEffekte.nikolaustag(2025)   # Samstag → Freitag
        assert_equal Date.new(2026, 12, 7), MonitorEffekte.nikolaustag(2026)   # Sonntag → Montag
        assert_equal({:fest => 'nikolaus', :nah => true}, MonitorEffekte.fest(Date.new(2026, 12, 7)))
        assert_equal({:fest => 'weihnachten', :nah => false}, MonitorEffekte.fest(Date.new(2026, 12, 6)))
        assert_equal({:fest => 'weihnachten', :nah => false}, MonitorEffekte.fest(Date.new(2026, 12, 8)))
        assert_equal [nil, {:fest => 'nikolaus', :nah => true}, 'wetter'],
                     MonitorEffekte.vorrang({:effekt => 'schnee', :staerke => 1}, {:fest => 'nikolaus', :nah => true})
    end

    def test_first_school_day_after_summer_until_noon
        ferien = [{:title => 'Sommerferien', :from => '2027-07-08', :to => '2027-08-20'}]
        assert_equal Date.new(2027, 8, 23), MonitorEffekte.erster_schultag_nach_sommerferien(2027, ferien)
        tag = Date.new(2027, 8, 23)
        assert_equal({:fest => 'schulanfang', :nah => true}, MonitorEffekte.fest(tag, ferien))
        assert_equal({:fest => 'schulanfang', :nah => true}, MonitorEffekte.fest(tag, ferien, Time.new(2027, 8, 23, 11, 59)))
        assert_nil MonitorEffekte.fest(tag, ferien, Time.new(2027, 8, 23, 12, 0))
        assert_nil MonitorEffekte.fest(Date.new(2027, 8, 24), ferien, Time.new(2027, 8, 24, 9, 0))
        assert_equal [nil, {:fest => 'schulanfang', :nah => true}, 'wetter'],
                     MonitorEffekte.vorrang({:effekt => 'hitze', :staerke => 2}, {:fest => 'schulanfang', :nah => true})
    end

    def test_rain_storm_and_freezing_rain_map_to_the_right_effect
        art = ->(ereignis) { MonitorEffekte.effekt_art('event' => ereignis) }
        %w(STARKREGEN DAUERREGEN).each { |e| assert_equal 'regen', art.call(e) }
        assert_equal 'regen', art.call('EXTREM ERGIEBIGER DAUERREGEN')
        assert_equal 'frost', art.call('GEFRIERENDER REGEN')
        assert_equal 'frost', art.call('GLATTEIS')
        assert_equal 'schnee', art.call('SCHNEEREGEN')
        %w(ORKANBÖEN STURMBÖEN WINDBÖEN STARKWIND).each { |e| assert_equal 'sturm', art.call(e) }
        assert_equal 'sturm', art.call('EXTREME ORKANBÖEN')
        assert_equal 'gewitter', art.call('SCHWERES GEWITTER mit ORKANBÖEN')
    end

    def test_school_dates_beat_feasts_and_weather
        termine = [{:datum => '2026-12-09', :motiv => 'adventskonzert', :titel => 'Adventskonzert'},
                   {:datum => '2027-02-24', :motiv => 'forschertag', :titel => ''},
                   {:datum => '2027-03-01', :motiv => 'unbekannt'}]
        assert_equal({:fest => 'adventskonzert', :nah => true}, MonitorEffekte.schultermin(Date.new(2026, 12, 9), termine))
        assert_equal({:fest => 'forschertag', :nah => true}, MonitorEffekte.schultermin(Date.new(2027, 2, 24), termine))
        assert_nil MonitorEffekte.schultermin(Date.new(2027, 3, 1), termine)
        assert_nil MonitorEffekte.schultermin(Date.new(2026, 12, 10), termine)
        assert_nil MonitorEffekte.schultermin(Date.new(2026, 12, 9), nil)
        # Forschertage über drei Tage
        drei = [{:datum => '2027-06-14', :bis => '2027-06-16', :motiv => 'forschertag'}]
        assert_nil MonitorEffekte.schultermin(Date.new(2027, 6, 13), drei)
        (14..16).each { |d| assert_equal 'forschertag', MonitorEffekte.schultermin(Date.new(2027, 6, d), drei)[:fest] }
        assert_nil MonitorEffekte.schultermin(Date.new(2027, 6, 17), drei)
        assert_equal [nil, {:fest => 'adventskonzert', :nah => true}, 'wetter'],
                     MonitorEffekte.vorrang({:effekt => 'schnee', :staerke => 2}, {:fest => 'adventskonzert', :nah => true})
    end

    def test_easter_sunday
        assert_equal Date.new(2026, 4, 5), MonitorEffekte.ostersonntag(2026)
        assert_equal Date.new(2027, 3, 28), MonitorEffekte.ostersonntag(2027)
        assert_equal Date.new(2028, 4, 16), MonitorEffekte.ostersonntag(2028)
        assert_equal Date.new(2038, 4, 25), MonitorEffekte.ostersonntag(2038)
    end

    def test_feasts
        assert_nil MonitorEffekte.fest(Date.new(2026, 11, 30))
        assert_equal({:fest => 'weihnachten', :nah => false}, MonitorEffekte.fest(Date.new(2026, 12, 1)))
        assert_equal({:fest => 'weihnachten', :nah => false}, MonitorEffekte.fest(Date.new(2026, 12, 15)))
        assert_equal({:fest => 'weihnachten', :nah => true}, MonitorEffekte.fest(Date.new(2026, 12, 16)))
        assert_equal({:fest => 'weihnachten', :nah => true}, MonitorEffekte.fest(Date.new(2026, 12, 18)))
        assert_nil MonitorEffekte.fest(Date.new(2026, 12, 27))
        assert_nil MonitorEffekte.fest(Date.new(2027, 3, 13))
        assert_equal({:fest => 'ostern', :nah => false}, MonitorEffekte.fest(Date.new(2027, 3, 15)))
        assert_equal({:fest => 'ostern', :nah => true}, MonitorEffekte.fest(Date.new(2027, 3, 26)))
        assert_equal 'ostern', MonitorEffekte.fest(Date.new(2027, 3, 29))[:fest]
        assert_nil MonitorEffekte.fest(Date.new(2027, 3, 30))
    end
end
