#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'json'
require 'zlib'
require 'fileutils'

class Timetable
    include QtsNeo4j
    
    def initialize
        @lesson_cache = []
        @lesson_events = nil
        update_timetables()
    end
    
    def strike(s)
        (s && s.size > 0) ? "<s>#{s}</s>" : s
    end
    
    def bold(s)
        (s && s.size > 0) ? "<b>#{s}</b>" : s
    end
    
    def paren(s)
        (s && s.size > 0) ? "(#{s})" : s
    end
    
    def fix_label_for_unicode(original)
        s = original.gsub('<b>', '').gsub('</b>', '')
        while true do
            i0 = s.index('<s>')
            break if i0.nil?
            i1 = s.index('</s>', i0)
            span = s[i0, i1 - i0 + 4]
            span = span.gsub('<s>', '').gsub('</s>', '').split('').map { |x| x + "\u0336" }.join('')
            s[i0, i1 - i0 + 4] = span
        end
        s.strip
    end

    def fix_h_to_hh(s)
        return nil if s.nil?
        if s =~ /^\d:\d\d$/
            '0' + s
        else
            s
        end
    end
    
    def gen_label_lehrer(a, b)
        # a: fach, b: lehrer
        a0 = ''; a1 = ''; b0 = []; b1 = [];
        begin; a0 = a.first; rescue; end;
        begin; a1 = a.last; rescue; end;
        begin; b0 = b.first || []; rescue; end;
        begin; b1 = b.last || []; rescue; end;
        s = if a0 == a1 && b0 == b1
            "#{bold(a0)} #{paren(b0.join(', '))}".strip
        elsif a0 == a1 && b0 != b1
            "#{bold(a0)} <s>(#{b0.join(', ')})</s> #{paren(b1.join(', '))}".strip
        elsif a0 != a1 && b0 == b1
            "#{strike(bold(a0))} #{bold(a1)} #{paren(b0.join(', '))}".strip
        else
            "#{strike(bold(a0) + ' ' + paren(b0.join(', ')))} #{bold(a1)} #{paren(b1.join(', '))}".strip
        end
        s.gsub('<s>()</s>', '').strip
    end
    
    def gen_label_klasse(a, b, c)
        # a: fach, b: klassen, c: lehrer
        b = [[]] if b.nil?
        b = [[]] if b == [nil]
        a0 = ''; a1 = ''; b0 = []; b1 = []; c0 = []; c1 = [];
        b = b.map do |x|
            x.map { |y| KLASSEN_TR[y] || y }
        end
        begin; a0 = a.first; rescue; end;
        begin; a1 = a.last; rescue; end;
        begin; b0 = b.first || []; rescue; end;
        begin; b1 = b.last || []; rescue; end;
        begin; c0 = c.first || []; rescue; end;
        begin; c1 = c.last || []; rescue; end;
        s = if a0 == a1 && b0 == b1
            "#{bold(a0)} #{paren(b0.join(', '))}".strip
        elsif a0 == a1 && b0 != b1
            ba = b0.dup
            b1.each { |b| ba << b unless ba.include?(b) }
            "#{bold(a0)} #{paren(ba.map { |x| b1.include?(x) ? x : '<s>' + x + '</s>' }.reject { |x| (x || '').strip.size == 0}.join(', '))}".strip
        elsif a0 != a1 && b0 == b1
            "#{strike(bold(a0))} #{bold(a1)} #{paren(b0.join(', '))}".strip
        else
            _temp = "#{strike(bold(a0))} #{bold(a1)}"
            ba = b0.dup
            b1.each { |b| ba << b unless ba.include?(b) }
            _temp += " #{paren(ba.map { |x| b1.include?(x) ? x : '<s>' + x + '</s>' }.reject { |x| (x || '').strip.size == 0}.join(', '))}"
            _temp.strip!
            _temp
        end
        if c0 != c1
            s += " #{strike(c0.join(', '))} #{c1.join(', ')}"
        end
        s.gsub('<s>()</s>', '').strip
    end
    
    def merge_same_events(cache_indices)
        # in / out: cache indices
        merged_event_indices = []
        cache_indices.sort do |_a, _b|
            a = @lesson_cache[_a]
            b = @lesson_cache[_b]
            sprintf("#{a[:fach]},#{a[:raum]},#{a[:label_klasse]},#{a[:label_lehrer]},%02d", a[:stunde]) <=> sprintf("#{b[:fach]},#{b[:raum]},#{b[:label_klasse]},#{b[:label_lehrer]},%02d", b[:stunde])
        end.each do |cache_index|
            event = @lesson_cache[cache_index]
            unless merged_event_indices.empty?
                last_event = @lesson_cache[merged_event_indices.last]
                if last_event[:fach] == event[:fach] &&
                    last_event[:raum] == event[:raum] &&
                    last_event[:klassen] == event[:klassen] &&
                    last_event[:lehrer] == event[:lehrer] &&
                    last_event[:label_lehrer] == event[:label_lehrer] &&
                    last_event[:label_klasse] == event[:label_klasse] &&
                    last_event[:vertretungs_text] == event[:vertretungs_text] &&
                    last_event[:stunde] + last_event[:count] == event[:stunde]
                    
                    a = last_event[:start].split('T')[1].split(':').map { |x| x.to_i }
                    a = a[0] * 60 + a[1]
                    b = last_event[:end].split('T')[1].split(':').map { |x| x.to_i }
                    b = b[0] * 60 + b[1]
                    c = event[:start].split('T')[1].split(':').map { |x| x.to_i }
                    c = c[0] * 60 + c[1]
                    pause = [b - a, c - a]
                    if (pause[0] - pause[1]).abs > 5
                        last_event[:pausen] ||= []
                        last_event[:pausen] << pause
                    end
                    last_event[:count] += 1
                    last_event[:end] = event[:end]
                    if event[:hausaufgaben_text]
                        last_event[:hausaufgaben_text] ||= Set.new()
                        last_event[:hausaufgaben_text] |= event[:hausaufgaben_text]
                    end
                    if event[:homework_est_time] && (!event[:homework_est_time].strip.empty?)
                        last_event[:homework_est_time] ||= '0'
                        last_event[:homework_est_time] = (last_event[:homework_est_time].to_i + event[:homework_est_time].to_i).to_s
                    end
                    if event[:stundenthema_text]
                        last_event[:stundenthema_text] ||= Set.new()
                        last_event[:stundenthema_text] |= event[:stundenthema_text]
                    end
                    if event[:notizen]
                        last_event[:notizen] ||= Set.new()
                        last_event[:notizen] |= event[:notizen]
                    end
                    event[:deleted] = true
                else
                    merged_event_indices << cache_index
                end
            else
                merged_event_indices << cache_index
            end
        end
        Set.new(merged_event_indices)
    end
    
    def update_monitor()
        debug "Updating monitor..."

        monitor_date = Date.parse([@@config[:first_school_day], Date.today.to_s].max.to_s)
        if DEVELOPMENT
            monitor_date = Date.parse('2021-08-30')
        end
        while [6, 0].include?(monitor_date.wday)
            monitor_date += 1
        end
        monitor_date = monitor_date.strftime('%Y-%m-%d')

        monitor_timestamp = ''
        monitor_data = {:klassen => {}, :lehrer => {}, :timestamp => DateTime.now.to_s}
        vplan_timestamp_path = '/vplan/timestamp.txt'
        if File.exists?(vplan_timestamp_path)
            vplan_timestamp = File.read(vplan_timestamp_path)
            parts = vplan_timestamp.split('-')

            monitor_data[:vplan_timestamp] = DateTime.parse("#{parts[0]}-#{parts[1]}-#{parts[2]}T#{parts[3]}:#{parts[4]}:#{parts[5]}+#{DateTime.now.to_s.split('+')[1]}").to_s
        end

        temp_data = {:klassen => {}, :lehrer => {}}
        (@@vertretungen[monitor_date] || []).sort do |a, b|
            a[:stunde] <=> b[:stunde]
        end.each do |ventry|
            klassen = Set.new(ventry[:klassen_alt] || []) | Set.new(ventry[:klassen_neu] || [])
            klassen.each do |klasse|
                next unless KLASSEN_ORDER.include?(klasse)
                temp_data[:klassen][klasse] ||= {}
                key = ventry.keys.sort.reject { |k| k == :stunde }.map { |k| [k, ventry[k]] }.to_json
                temp_data[:klassen][klasse][key] ||= []
                temp_data[:klassen][klasse][key] << ventry
            end
            lehrer = Set.new(ventry[:lehrer_alt] || []) | Set.new(ventry[:lehrer_neu] || [])
            lehrer.each do |shorthand|
                next unless @@shorthands.include?(shorthand)
                temp_data[:lehrer][shorthand] ||= {}
                key = ventry.keys.sort.reject { |k| k == :stunde }.map { |k| [k, ventry[k]] }.to_json
                temp_data[:lehrer][shorthand][key] ||= []
                temp_data[:lehrer][shorthand][key] << ventry
            end
        end
        [:klassen, :lehrer].each do |which|
            temp_data[which].each_pair do |key, entries|
                monitor_data[which][key] = []
                entries.values.each do |tuple|
                    tuple.each.with_index do |entry, i|
                        if i > 0
                            if monitor_data[which][key].last[:stunde_range].last + 1 == entry[:stunde]
                                monitor_data[which][key].last[:stunde_range][1] += 1
                            else
                                monitor_data[which][key] << entry
                                monitor_data[which][key].last[:stunde_range] = [monitor_data[which][key].last[:stunde], monitor_data[which][key].last[:stunde]]
                            end
                        else
                            monitor_data[which][key] << entry
                            monitor_data[which][key].last[:stunde_range] = [monitor_data[which][key].last[:stunde], monitor_data[which][key].last[:stunde]]
                        end
                    end
                end
                monitor_data[which][key].map! do |entry|
                    if entry[:stunde_range].first == entry[:stunde_range].last
                        entry[:stunde_label] = "#{entry[:stunde_range].first}."
                    else
                        entry[:stunde_label] = "#{entry[:stunde_range].first}. – #{entry[:stunde_range].last}."
                    end
                    entry.delete(:stunde_range)
                    entry
                end
            end
        end
        # temp_data[:klassen].each_pair do |klasse, entries|
        #     monitor_data[:klassen][klasse] = []
        #     entries.values.each do |tuple|
        #         tuple.each.with_index do |entry, i|
        #             if i > 0
        #                 if monitor_data[:klassen][klasse].last[:stunde_range].last + 1 == entry[:stunde]
        #                     monitor_data[:klassen][klasse].last[:stunde_range][1] += 1
        #                 else
        #                     monitor_data[:klassen][klasse] << entry
        #                     monitor_data[:klassen][klasse].last[:stunde_range] = [monitor_data[:klassen][klasse].last[:stunde], monitor_data[:klassen][klasse].last[:stunde]]
        #                 end
        #             else
        #                 monitor_data[:klassen][klasse] << entry
        #                 monitor_data[:klassen][klasse].last[:stunde_range] = [monitor_data[:klassen][klasse].last[:stunde], monitor_data[:klassen][klasse].last[:stunde]]
        #             end
        #         end
        #     end
        #     monitor_data[:klassen][klasse].map! do |entry|
        #         if entry[:stunde_range].first == entry[:stunde_range].last
        #             entry[:stunde_label] = "#{entry[:stunde_range].first}."
        #         else
        #             entry[:stunde_label] = "#{entry[:stunde_range].first}. – #{entry[:stunde_range].last}."
        #         end
        #         entry.delete(:stunde_range)
        #         entry
        #     end
        # end
        # temp_data[:lehrer].each_pair do |shorthand, entries|
        #     monitor_data[:lehrer][shorthand] = []
        #     entries.values.each do |tuple|
        #         tuple.each.with_index do |entry, i|
        #             if i > 0
        #                 if monitor_data[:lehrer][shorthand].last[:stunde_range].last + 1 == entry[:stunde]
        #                     monitor_data[:lehrer][shorthand].last[:stunde_range][1] += 1
        #                 else
        #                     monitor_data[:lehrer][shorthand] << entry
        #                     monitor_data[:lehrer][shorthand].last[:stunde_range] = [monitor_data[:lehrer][shorthand].last[:stunde], monitor_data[:lehrer][shorthand].last[:stunde]]
        #                 end
        #             else
        #                 monitor_data[:lehrer][shorthand] << entry
        #                 monitor_data[:lehrer][shorthand].last[:stunde_range] = [monitor_data[:lehrer][shorthand].last[:stunde], monitor_data[:lehrer][shorthand].last[:stunde]]
        #             end
        #         end
        #     end
        #     monitor_data[:lehrer][shorthand].map! do |entry|
        #         if entry[:stunde_range].first == entry[:stunde_range].last
        #             entry[:stunde_label] = "#{entry[:stunde_range].first}."
        #         else
        #             entry[:stunde_label] = "#{entry[:stunde_range].first}. – #{entry[:stunde_range].last}."
        #         end
        #         entry.delete(:stunde_range)
        #         entry
        #     end
        # end
        FileUtils.mkpath('/vplan/monitor')
        File.open('/vplan/monitor/monitor.json', 'w') { |f| f.write(monitor_data.to_json) }
        if ENV['DASHBOARD_SERVICE'] == 'timetable'
            STDERR.puts "service: [#{ENV['DASHBOARD_SERVICE']}]"
            system("curl -s http://ruby:3000/api/update_monitors")
        end
        # update_monitors()
    end

    def update_timetables()
        debug "Updating timetables..."
        # refresh vplan data
        Main.collect_data()
        @@ferien_feiertage = Main.class_variable_get(:@@ferien_feiertage)
        @@tage_infos = Main.class_variable_get(:@@tage_infos)
        @@config = Main.class_variable_get(:@@config)
        @@user_info = Main.class_variable_get(:@@user_info)
        @@lessons = Main.class_variable_get(:@@lessons)
        @@vertretungen = Main.class_variable_get(:@@vertretungen)
        @@vplan_timestamp = Main.class_variable_get(:@@vplan_timestamp)
        @@day_messages = Main.class_variable_get(:@@day_messages)
        @@lessons_for_klasse = Main.class_variable_get(:@@lessons_for_klasse)
        @@lessons_for_user = Main.class_variable_get(:@@lessons_for_user)
        @@lessons_for_shorthand = Main.class_variable_get(:@@lessons_for_shorthand)
        @@shorthands = Main.class_variable_get(:@@shorthands)
        @@klassen_order = Main.class_variable_get(:@@klassen_order)
        @@klassen_id = Main.class_variable_get(:@@klassen_id)
        @@faecher = Main.class_variable_get(:@@faecher)
        @@klassen_for_shorthand = Main.class_variable_get(:@@klassen_for_shorthand)
        @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        @@schueler_for_lesson = Main.class_variable_get(:@@schueler_for_lesson)
        @@teachers_for_klasse = Main.class_variable_get(:@@teachers_for_klasse)
        @@schueler_offset_in_lesson = Main.class_variable_get(:@@schueler_offset_in_lesson)
        @@pausenaufsichten = Main.class_variable_get(:@@pausenaufsichten)
        @@tablets = Main.class_variable_get(:@@tablets)
        @@tablet_sets = Main.class_variable_get(:@@tablet_sets)
        
        lesson_offset = {}

        @lesson_cache = []
        @lesson_events = {}
        @lesson_events_regular = {}
        hfk_ds = HOURS_FOR_KLASSE.keys.sort.first

        update_monitor()
        
        Main.iterate_school_days do |ds, dow|
            HOURS_FOR_KLASSE.keys.sort.each do |k|
                hfk_ds = k if ds >= k
            end
            ds_date = Date.parse(ds)
            ds_yw = ds_date.strftime('%Y-%V')
            day_events = {}
            day_lesson_keys_for_stunde = {}
            day_events_regular = {}
            # 1. add all regular lessons for today
            @@lessons[:lesson_keys].each_pair do |lesson_key, lesson_info|
                unr = lesson_info[:unr]
                lesson_offset[lesson_key] ||= 0
                start_date = @@lessons[:start_date_for_date][ds]
                next if start_date.nil?
                lesson = @@lessons[:timetables][start_date][lesson_key]
                next if lesson.nil? || lesson[:stunden][dow].nil?
                lesson[:stunden][dow].keys.sort.each.with_index do |stunde, o|
                    entry = lesson[:stunden][dow][stunde]
                    hfk_klasse = entry[:klassen].first
                    if HOURS_FOR_KLASSE[hfk_ds][hfk_klasse]
                        entry[:start_time] = HOURS_FOR_KLASSE[hfk_ds][hfk_klasse][stunde][0]
                        entry[:end_time] = HOURS_FOR_KLASSE[hfk_ds][hfk_klasse][stunde][1]
                    else
                        entry[:start_time] = HOURS_FOR_KLASSE[hfk_ds]['7a'][stunde][0]
                        entry[:end_time] = HOURS_FOR_KLASSE[hfk_ds]['7a'][stunde][1]
                    end
                    event = {
                        :lesson => true,
                        :datum => ds,
                        :stunde => stunde,
                        :start => "#{ds}T#{entry[:start_time]}",
                        :end => "#{ds}T#{entry[:end_time]}",
                        :fach => ["#{lesson_info[:fach]}"],
                        :raum => ["#{entry[:raum]}"],
                        :klassen => [entry[:klassen].to_a.sort],
                        :lehrer => [entry[:lehrer].to_a.sort],
                        :lesson_key => lesson_key,
                        :orig_lesson_key => lesson_key,
                        :lesson_offset => nil,
                        :count => entry[:count],
                        :cache_index => @lesson_cache.size,
                        :regular => false
                    }
                    @lesson_cache << event
                    event[:pausen] = entry[:pausen] unless entry[:pausen].empty?
                    day_events[stunde] ||= Set.new()
                    day_events[stunde] << event[:cache_index]
                    day_lesson_keys_for_stunde
                    day_lesson_keys_for_stunde[stunde] ||= Set.new()
                    day_lesson_keys_for_stunde[stunde] << lesson_key
                    
                    event_regular = {
                        :lesson => true,
                        :datum => ds,
                        :stunde => stunde,
                        :start => "#{ds}T#{entry[:start_time]}",
                        :end => "#{ds}T#{entry[:end_time]}",
                        :fach => "#{lesson_info[:fach]}",
                        :raum => "#{entry[:raum]}",
                        :klassen => entry[:klassen].to_a.sort,
                        :lehrer => entry[:lehrer].to_a.sort,
                        :lesson_key => lesson_key,
                        :count => entry[:count],
                        :cache_index => @lesson_cache.size,
                        :regular => true
                    }
                    @lesson_cache << event_regular
                    day_events_regular[stunde] ||= Set.new()
                    day_events_regular[stunde] << event_regular[:cache_index]
                end
            end
            
            # # 1b. add all Pausenaufsichten for today
            start_date = @@pausenaufsichten[:start_date_for_date][ds]
            if start_date
                @@pausenaufsichten[:aufsichten][start_date].each_pair do |shorthand, entries|
                    (entries[dow] || {}).each_pair do |stunde, entry|
                        # STDERR.puts "#{shorthand} #{stunde} #{entry.to_json}"
                        event = {
                            :lesson => true,
                            :datum => ds,
                            :stunde => stunde,
                            :pausenaufsicht => true,
                            :fach => ['Pausenaufsicht'],
                            :start => "#{ds}T#{entry[:start_time]}",
                            :end => "#{ds}T#{entry[:end_time]}",
                            :raum => [entry[:where]],
                            :lehrer => [[shorthand]],
                            :lesson_key => 0,
                            :cache_index => @lesson_cache.size,
                            :count => 1,
                            :regular => false
                        }
                        @lesson_cache << event
                        day_events[stunde] ||= Set.new()
                        day_events[stunde] << event[:cache_index]
                    end
                end
            end

            # 2. patch today's lessons based on vertretungsplan
            if @@vertretungen[ds]
                @@vertretungen[ds].each do |ventry|
                    handled_ventry = false
                    if ventry[:before_stunde]
                        # ventry refers to a Pausenaufsichtsvertretung
                        matching_indices = (day_events[ventry[:stunde]] || []).select do |index|
                            event = @lesson_cache[index]
                            flag = false
                            if event[:pausenaufsicht]
                                if event[:stunde] == ventry[:stunde]
                                    vlehrer = ventry[:lehrer_alt]
                                    unless (Set.new(event[:lehrer].last) & Set.new(vlehrer)).empty?
                                        flag = true
                                    end
                                end
                            end
                            flag
                        end
                        if matching_indices.size == 1
                            event = @lesson_cache[matching_indices.first]
                            # LEHRER
                            event[:lehrer] = [ventry[:lehrer_alt] || [], ventry[:lehrer_neu] || []]
                            if ventry[:vertretungs_text]
                                event[:vertretungs_text] = ventry[:vertretungs_text]
                            end
                            handled_ventry = true
                        end
                    end
                    unless handled_ventry
                        # ventry refers to a lesson OR we did not find a matching pausenaufsicht
                        # find matching day_events entry (the lesson that matches this ventry)
                        matching_indices = (day_events[ventry[:stunde]] || []).select do |index|
                            event = @lesson_cache[index]
                            flag = false
                            if !event[:regular] 
                                if event[:stunde] == ventry[:stunde]
                                    vfach = ventry[:fach_alt] || ventry[:fach_neu]
                                    if (event[:fach] || []).first == vfach
                                        vlehrer = ventry[:lehrer_alt] || ventry[:lehrer_neu] || []
                                        unless (Set.new(event[:lehrer].first) & Set.new(vlehrer)).empty?
                                            flag = true
                                        end
                                    end
                                end
                            end
                            flag
                        end
                        if matching_indices.size == 1
                            event = @lesson_cache[matching_indices.first]
                            # LEHRER
                            if ventry[:lehrer_alt] && ventry[:lehrer_neu].nil?
                                event[:lehrer] = [ventry[:lehrer_alt], []]
                            elsif ventry[:lehrer_alt] && ventry[:lehrer_neu] 
                                # Lehrerwechsel
                                event[:lehrer] = [ventry[:lehrer_alt], ventry[:lehrer_neu] ]
                            elsif ventry[:lehrer_alt].nil? && ventry[:lehrer_neu] 
                                # Lehrerwechsel: mehr Lehrer als vorher
                                event[:lehrer] = [[], ventry[:lehrer_neu] ]
                            end

                            # KLASSEN
                            if ventry[:klassen_alt] && ventry[:klassen_neu].nil?
                                event[:klassen] = [ventry[:klassen_alt], []]
                            elsif ventry[:klassen_alt] && ventry[:klassen_neu] 
                                # Klassenwechsel
                                event[:klassen] = [ventry[:klassen_alt], ventry[:klassen_neu] ]
                            elsif ventry[:klassen_alt].nil? && ventry[:klassen_neu] 
                                # Klassenwechsel: mehr Klassen
                                event[:klassen] = [[], ventry[:klassen_neu] ]
                            end

                            # FACH
                            if ventry[:fach_alt] && ventry[:fach_neu]
                                # Fachwechsel
                                event[:fach] = [ventry[:fach_alt], ventry[:fach_neu] ]
                                matching_lesson_keys = Set.new()
                                ventry[:klassen_neu].each do |klasse|
                                    (@@lessons_for_klasse[klasse] || []).each do |fach|
                                        if fach.split('_').first == ventry[:fach_neu]
                                            matching_lesson_keys << fach
                                        end
                                    end
                                end
                                if matching_lesson_keys.size == 1
                                    # update lesson_key
                                    event[:lesson_key] = matching_lesson_keys.to_a.first
                                else
                                    # WARN no matching lesson key found OR more than one
                                end
                            end
                            if ventry[:fach_alt] && ventry[:fach_neu].nil?
                                event[:fach] = [ventry[:fach_alt], ventry[:fach_neu] ]
                            end

                            # RAUM
                            if ventry[:raum_alt] && ventry[:raum_neu] 
                                # Raumwechsel
                                event[:raum] = [ventry[:raum_alt], ventry[:raum_neu] ]
                            end

                            # Vertretungstext
                            if ventry[:vertretungs_text]
                                event[:vertretungs_text] = ventry[:vertretungs_text]
                            end
                        elsif matching_indices.size == 0
                            # We found no matching indices, add as custom entry
                            hfk_klasse = nil
                            hfk_klasse = ventry[:klassen_neu].first if ventry[:klassen_neu]
                            start_time = nil
                            end_time = nil
                            if (HOURS_FOR_KLASSE[hfk_ds] || {})[hfk_klasse]
                                start_time = HOURS_FOR_KLASSE[hfk_ds][hfk_klasse][ventry[:stunde]][0]
                                end_time = HOURS_FOR_KLASSE[hfk_ds][hfk_klasse][ventry[:stunde]][1]
                            else
                                start_time = HOURS_FOR_KLASSE[hfk_ds]['7a'][ventry[:stunde]][0]
                                end_time = HOURS_FOR_KLASSE[hfk_ds]['7a'][ventry[:stunde]][1]
                            end
                            event = {
                                :lesson => true,
                                :datum => ventry[:datum],
                                :stunde => ventry[:stunde],
                                :start => "#{ds}T#{start_time}",
                                :end => "#{ds}T#{end_time}",
                                :fach => ["#{ventry[:fach_alt]}", "#{ventry[:fach_neu]}"],
                                :raum => ["#{ventry[:raum_alt]}", "#{ventry[:raum_neu]}"],
                                :klassen => [ventry[:klassen_alt].to_a.sort, ventry[:klassen_neu].to_a.sort],
                                :lehrer => [ventry[:lehrer_alt] || [], ventry[:lehrer_neu] || []],
                                :lesson_key => 0,
                                :lesson_offset => nil,
                                :count => 1,
                                :cache_index => @lesson_cache.size,
                                :vertretungs_text => ventry[:vertretungs_text],
                                :regular => false
                            }
                            @lesson_cache << event
                            day_events[ventry[:stunde]] ||= Set.new()
                            day_events[ventry[:stunde]] << event[:cache_index]
                        else
                            # We found NO matching lesson entry
                        end
                    end
                end
            end

            # mark lessons as 'entfall'
            day_events.each_pair do |stunde, event_indices|
                event_indices.each do |cache_index|
                    e = @lesson_cache[cache_index]
                    if e[:lesson] && e[:lesson_key] && e[:lesson_key] != 0
                        if (e[:klassen] && e[:klassen][1] && e[:klassen][1].empty?) || (e[:lehrer] && e[:lehrer][1] && e[:lehrer][1].empty?)
                            e[:entfall] = true
                            e[:lesson_key] = 0
                        end
                    end
                    if e[:lehrer] 
                        if e[:lehrer][0]
                            e[:lehrer][0].sort!
                        end
                        if e[:lehrer][1]
                            e[:lehrer][1].sort!
                        end
                    end
                end
            end

            # 2b. patch fach, raum, klassen, lehrer
            day_events.each_pair do |stunde, event_indices|
                event_indices.each do |cache_index|
                    e = @lesson_cache[cache_index]
                    e[:lehrer_list] = Set.new((e[:lehrer] || []).flatten)
                    e[:klassen_list] = Set.new((e[:klassen] || []).flatten)
                    if e[:lehrer] && e[:lehrer].size > 1
                        e[:lehrer_removed] = e[:lehrer].first
                    end
                    if e[:klassen] && e[:klassen].size > 1
                        e[:klassen_removed] = e[:klassen].first
                    end

                    fach_lang = e[:fach].map do |x|
                        @@faecher[x] || x
                    end
                    lehrer_lang = e[:lehrer].map do |x|
                        x.map do |y|
                            (@@user_info[@@shorthands[y]] || {})[:display_last_name] || y
                        end
                    end
                    e[:label_lehrer_short] = gen_label_lehrer(e[:fach], e[:lehrer])
                    e[:label_klasse_short] = gen_label_klasse(e[:fach], e[:klassen], e[:lehrer])
                    e[:label_lehrer] = gen_label_lehrer(fach_lang, e[:lehrer])
                    e[:label_klasse] = gen_label_klasse(fach_lang, e[:klassen], e[:lehrer])
                    e[:label_lehrer_lang] = gen_label_lehrer(fach_lang, lehrer_lang)
                    e[:label_klasse_lang] = gen_label_klasse(fach_lang, e[:klassen], lehrer_lang)
                    [:raum].each do |k|
                        if e[k].first == e[k].last
                            e[k] = e[k].first
                        else
                            e[k] = "#{strike(e[k].first)} #{e[k].last}".strip
                        end
                    end
                    
                    e.delete(:fach)
                    e.delete(:lehrer)
                    
                    lesson_key = e[:lesson_key]
                    if lesson_key && lesson_key != 0
                        lesson_info = @@lessons[:lesson_keys][lesson_key]
                        fach = lesson_info[:fach]
                        fach = @@faecher[fach] || fach
                        e[:nc_folder] = {
                            :teacher => "#{fach} (#{lesson_info[:klassen].sort.join(', ')})",
                            :sus => "#{fach}"
                        }
                        e[:nc_collect_folder] = {
                            :teacher => "Auto-Einsammelordner (von SuS an mich)",
                            :sus => "Einsammelordner"
                        }
                        e[:nc_return_folder] = {
                            :teacher => "Auto-Rückgabeordner (von mir an SuS)",
                            :sus => "Rückgabeordner"
                        }
                    end                    
                end
            end
            day_events_regular.each_pair do |stunde, event_indices|
                event_indices.each do |cache_index|
                    e = @lesson_cache[cache_index]
                    fach_lang = @@faecher[e[:fach]] || e[:fach]
                    lehrer_lang = e[:lehrer].map do |y|
                        (@@user_info[@@shorthands[y]] || {})[:display_last_name] || y
                    end
                    e[:label_lehrer_short] = gen_label_lehrer([e[:fach]], [e[:lehrer]])
                    e[:label_klasse_short] = gen_label_klasse([e[:fach]], [e[:klassen]], [e[:lehrer]])
                    e[:label_lehrer] = gen_label_lehrer([fach_lang], [e[:lehrer]])
                    e[:label_klasse] = gen_label_klasse([fach_lang], [e[:klassen]], [e[:lehrer]])
                    e[:label_lehrer_lang] = gen_label_lehrer([fach_lang], [lehrer_lang])
                    e[:label_klasse_lang] = gen_label_klasse([fach_lang], [e[:klassen]], [lehrer_lang])
                    e[:klassen] = [e[:klassen]]
                    
                    e.delete(:fach)
                    e.delete(:lehrer)
                end
            end
            
            day_events_by_lesson_key = {}
            day_events.each_pair do |stunde, event_indices|
                event_indices.each do |cache_index|
                    event = @lesson_cache[cache_index]
                    day_events_by_lesson_key[event[:lesson_key]] ||= Set.new()
                    day_events_by_lesson_key[event[:lesson_key]] << cache_index
                end
            end

            day_events = day_events_by_lesson_key
            # ----------------------------------------------------------------------------
            # ATTENTION: FROM HERE ON, day_events are associated by lesson_key, not stunde
            # ----------------------------------------------------------------------------
            
            day_events_regular_by_lesson_key = {}
            day_events_regular.each_pair do |stunde, event_indices|
                event_indices.each do |cache_index|
                    event = @lesson_cache[cache_index]
                    day_events_regular_by_lesson_key[event[:lesson_key]] ||= Set.new()
                    day_events_regular_by_lesson_key[event[:lesson_key]] << cache_index
                end
            end
            day_events_regular = day_events_regular_by_lesson_key
            
            # 2c. sort events # NOT NECESSARY
#             day_events.each_pair do |lesson_key, events|
#                 events.sort! do |a, b|
#                     a[:stunde] <=> b[:stunde]
#                 end
#             end
#             
            # 2c. find doppelstunden
            day_events.each_pair do |lesson_key, event_indices|
                next if lesson_key == 0
                day_events[lesson_key] = merge_same_events(event_indices.to_a.sort)
                day_events[lesson_key].each do |cache_index|
                    e = @lesson_cache[cache_index]
                    if e[:hausaufgaben_text]
                        e[:hausaufgaben_text] = e[:hausaufgaben_text].to_a.join('<br />')
                    end
                    if e[:stundenthema_text]
                        e[:stundenthema_text] = e[:stundenthema_text].to_a.join('<br />')
                    end
                    if e[:notizen]
                        e[:notizen] = e[:notizen].to_a.join('<br />')
                    end
                end
            end
            
            day_events_regular.each_pair do |lesson_key, event_indices|
                day_events_regular[lesson_key] = merge_same_events(event_indices.to_a.sort)
            end
            
            day_events_special = {}

            # 3. add today's events to lesson_events, collect lehrer and klassen events
            day_events.each_pair do |lesson_key, event_indices|
                if lesson_key != 0
                    @lesson_events[lesson_key] ||= {}
                    @lesson_events[lesson_key][ds_yw] ||= Set.new()
                    @lesson_events[lesson_key][ds_yw] += event_indices
                end
                event_indices.each do |cache_index|
                    event = @lesson_cache[cache_index]
                    (event[:lehrer_list] || Set.new()).each do |lehrer|
                        key = "_#{lehrer}"
                        day_events_special[key] ||= Set.new()
                        day_events_special[key] << cache_index
                    end
                    (event[:klassen_list] || Set.new()).each do |klasse|
                        key = "_#{klasse}"
                        day_events_special[key] ||= Set.new()
                        day_events_special[key] << cache_index
                    end
                end
            end
            day_events_regular.each_pair do |lesson_key, event_indices|
                @lesson_events_regular[lesson_key] ||= {}
                @lesson_events_regular[lesson_key][ds_yw] ||= Set.new()
                @lesson_events_regular[lesson_key][ds_yw] += event_indices
            end

            # 3b. merge same lehrer and klassen events and add them to lesson_events
            day_events_special.each_pair do |key, event_indices|
                day_events_special[key] = merge_same_events(event_indices)
                @lesson_events[key] ||= {}
                @lesson_events[key][ds_yw] ||= Set.new()
                @lesson_events[key][ds_yw] += day_events_special[key]
            end
            
            # 4. increment lesson offsets
            day_events.each_pair do |lesson_key, event_indices|
                next if lesson_key == 0
                events = event_indices.map { |x| @lesson_cache[x] }
                events.sort do |a, b|
                    a[:stunde] <=> b[:stunde]
                end.each do |event|
                    next if event[:pausenaufsicht]
                    event[:lesson_offset] = lesson_offset[lesson_key]
                    lesson_offset[lesson_key] += event[:count]
                end
            end
            
        end
        @events_by_lesson_key_and_offset = {}
        @regular_days_for_lesson_key = {}
        @lesson_cache.each.with_index do |event, cache_index|
            next if event[:lesson_offset].nil?
            @events_by_lesson_key_and_offset[event[:lesson_key]] ||= {}
            @events_by_lesson_key_and_offset[event[:lesson_key]][event[:lesson_offset]] = cache_index
        end
        @lesson_events_regular.each_pair do |lesson_key, ds_yw_info|
            ds_yw_info.values.each do |cache_indices|
                cache_indices.each do |cache_index|
                    event = @lesson_cache[cache_index]
                    @regular_days_for_lesson_key[event[:lesson_key]] ||= Set.new()
                    @regular_days_for_lesson_key[event[:lesson_key]] << event[:datum]
                end
            end
        end
        @regular_days_for_lesson_key.keys.each do |lesson_key|
            @regular_days_for_lesson_key[lesson_key] = @regular_days_for_lesson_key[lesson_key].to_a.sort
        end
        # Now purge all tablet bookings which have moved and send a message
        rows = neo4j_query(<<~END_OF_QUERY, {})
            MATCH (:Tablet)<-[:WHICH]-(b:Booking {confirmed: true})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            RETURN i.offset, l.key, b
        END_OF_QUERY
        rows.each do |row|
            lesson_key = row['l.key']
            offset = row['i.offset']
            booking = row['b'].props
            cache_index = (@events_by_lesson_key_and_offset[lesson_key] || {})[offset]
            if cache_index
                entry = @lesson_cache[cache_index]
                b0 = "#{booking[:datum]}T#{booking[:start_time]}"
                b1 = "#{booking[:datum]}T#{booking[:end_time]}"
                l0 = entry[:start]
                l1 = entry[:end]
                shorthands = @@lessons[:lesson_keys][lesson_key][:lehrer]
                if b0 != l0 || b1 != l1
                    ds = "#{b0[8, 2]}.#{b0[5, 2]}.#{b0[0, 4]}"
                    fach = entry[:label_klasse_lang].gsub(/<[^>]+>/, '').strip
                    # lesson has moved, purge the tablet booking
                    neo4j_query(<<~END_OF_QUERY, {:lesson_key => lesson_key, :offset => offset, :timestamp => Time.now.to_i})
                        MATCH (:Tablet)<-[:WHICH]-(b:Booking {confirmed: true})-[:FOR]->(i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {lesson_key}})
                        SET i.updated = {timestamp}
                        DETACH DELETE b;
                    END_OF_QUERY
                    shorthands.each do |shorthand|
                        email = @@shorthands[shorthand]
                        user_info = @@user_info[email]
                        deliver_mail do
                            to email
                            bcc SMTP_FROM
                            from SMTP_FROM
                            
                            subject "Tablet-Reservierung aufgehoben: #{fach}"

                            StringIO.open do |io|
                                io.puts "<p>Hallo!</p>"
                                io.puts "<p>Es tut mir leid, aber Ihre Lehrer-Tablet-Reservierung für #{fach} am #{ds} wurde aufgehoben, da die Stunde aufgrund von Änderungen am Vertretungsplan nun zu einem anderen Zeitpunkt stattfindet. Sie können ggfs. ein neues Tablet buchen.</p>"
                                io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                                io.string
                            end
                        end
                    end
                end
            end
        end

        # Now purge all tablet set bookings which have moved and send a message
        rows = neo4j_query(<<~END_OF_QUERY, {})
            MATCH (:TabletSet)<-[:BOOKED]-(b:Booking)-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            RETURN i.offset, l.key, b
        END_OF_QUERY
        purged_tablet_set_bookings = Set.new()
        rows.each do |row|
            lesson_key = row['l.key']
            offset = row['i.offset']
            booking = row['b'].props
            cache_index = (@events_by_lesson_key_and_offset[lesson_key] || {})[offset]
            if cache_index
                entry = @lesson_cache[cache_index]
                b0 = "#{booking[:datum]}T#{booking[:start_time]}"
                b1 = "#{booking[:datum]}T#{booking[:end_time]}"
                l0 = entry[:start]
                l1 = entry[:end]
                shorthands = @@lessons[:lesson_keys][lesson_key][:lehrer]
                if b0 != l0 || b1 != l1

                    # only cancel a tablet set booking once even if multiple tablet sets have been booked for that lesson
                    temp = "#{lesson_key}/#{offset}"
                    next if purged_tablet_set_bookings.include?(temp)
                    purged_tablet_set_bookings << temp

                    ds = "#{b0[8, 2]}.#{b0[5, 2]}.#{b0[0, 4]}"
                    fach = entry[:label_klasse_lang].gsub(/<[^>]+>/, '').strip
                    # lesson has moved, purge the tablet set booking
                    neo4j_query(<<~END_OF_QUERY, {:lesson_key => lesson_key, :offset => offset, :timestamp => Time.now.to_i})
                        MATCH (b:Booking)-[:FOR]->(i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {lesson_key}})
                        SET i.updated = {timestamp}
                        DETACH DELETE b;
                    END_OF_QUERY
                    shorthands.each do |shorthand|
                        email = @@shorthands[shorthand]
                        deliver_mail do
                            to email
                            bcc SMTP_FROM
                            from SMTP_FROM
                            
                            subject "Tabletsatz-Reservierung aufgehoben: #{fach}"

                            StringIO.open do |io|
                                io.puts "<p>Hallo!</p>"
                                io.puts "<p>Es tut mir leid, aber Ihre Lehrer-Tabletsatz-Reservierung für #{fach} am #{ds} wurde aufgehoben, da die Stunde aufgrund von Änderungen am Vertretungsplan nun zu einem anderen Zeitpunkt stattfindet. Sie können ggfs. einen neuen Tabletsatz buchen.</p>"
                                io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                                io.string
                            end
                        end
                    end
                end
            end
        end
    end
    
    def update_weeks(only_these_lesson_keys)
        debug "Updating weeks: #{only_these_lesson_keys.to_a.join(', ')}"
        
        ical_tokens = {}
        result = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User)
            WHERE EXISTS(u.ical_token)
            RETURN u.email, u.ical_token
        END_OF_QUERY
        result.each do |entry|
            next unless entry['u.ical_token'] =~ /^[a-zA-Z0-9]+$/
            ical_tokens[entry['u.email']] = entry['u.ical_token']
        end

        all_stream_restrictions = Main.get_all_stream_restrictions()
        all_homeschooling_users = Main.get_all_homeschooling_users()
        lesson_homework_feedback = {}
        
        group_for_sus = {}
        results = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User)
            RETURN u.email, COALESCE(u.group2, 'A') AS group2;
        END_OF_QUERY
        results.each do |x|
            group_for_sus[x['u.email']] = x['group2']
        end
        
        events_with_data_cache = {}
        events_with_data_per_user_cache = {}
        start_date = Date.parse(@@config[:first_day])
        end_date = Date.parse(@@config[:last_day])
        start_yw = start_date.strftime('%Y-%V')
        end_yw = end_date.strftime('%Y-%V')
        jitsi_count_for_dh = {}
        p = start_date
        while p.wday != 1
            p -= 1
        end
        file_count = 0
        today_date = Date.today.strftime('%Y-%m-%d')
        today_plus_7_days = (Date.today + TIMETABLE_ENTRIES_VISIBLE_AHEAD_DAYS + 1).strftime('%Y-%m-%d')
        regular_events_from = Date.today + TIMETABLE_ENTRIES_VISIBLE_AHEAD_DAYS + 1
        regular_events_from = regular_events_from.strftime('%Y-%m-%d')
        aufsicht_start_date_index = 0
        all_homework = {}
        @@lessons[:lesson_keys].keys.each do |lesson_key|
            (@lesson_info[lesson_key] || {}).keys.sort.each do |offset|
                data = @lesson_info[lesson_key][offset][:data] || {}
                collected = {}
                [:hausaufgaben_text, :homework_nc, :homework_lr].each do |k|
                    if data[k]
                        if data[k].class == String
                            unless data[k].strip.empty?
                                collected[k] = data[k]
                            end
                        else
                            if data[k]
                                collected[k] = data[k]
                            end
                        end
                    end
                end
                unless collected.empty?
                    [:homework_est_time].each do |k|
                        if data[k]
                            if data[k].class == String
                                unless data[k].strip.empty?
                                    collected[k] = data[k]
                                end
                            else
                                if data[k]
                                    collected[k] = data[k]
                                end
                            end
                        end
                    end
                    collected[:offset] = offset
                    cache_index = (@events_by_lesson_key_and_offset[lesson_key] || {})[offset]
                    if cache_index
                        datum = @lesson_cache[cache_index][:datum]
                        # if necessary, move datum to front until we hit a regular lesson
                        if datum >= regular_events_from
                            datum = @regular_days_for_lesson_key[lesson_key].select { |x| x <= datum }.last
                            datum = @regular_days_for_lesson_key[lesson_key].select { |x| x >= regular_events_from }.first if datum.nil?
                        end
                        all_homework[lesson_key] ||= {}
                        all_homework[lesson_key][datum] = collected
                    end
                end
            end
        end

        ical_events = {}
#         logged_emails = Set.new()
        while p <= end_date do
            p1 = p + 7
            p_yw = p.strftime('%Y-%V')
            # aufsicht_start_date_for_dow = {}
            # (0..4).each do |dow|
            #     pt = p + dow
            #     pt_s = pt.strftime('%Y-%m-%d')
            #     while aufsicht_start_date_index < @@pausenaufsichten[:start_dates].size - 1 && @@pausenaufsichten[:start_dates][aufsicht_start_date_index + 1] >= pt_s
            #         aufsicht_start_date_index += 1
            #     end
            #     aufsicht_start_date_for_dow[dow] = @@pausenaufsichten[:start_dates][aufsicht_start_date_index]
            # end
            holidays = []
            holiday_dates = Set.new()
            @@ferien_feiertage.each do |entry|
                unless (entry[:from] >= p1.strftime('%Y-%m-%d') || entry[:to] < p.strftime('%Y-%m-%d'))
                    holidays << {
                        :start => entry[:from],
                        :end => (Date.parse(entry[:to]) + 1).strftime('%Y-%m-%d'),
                        :title => entry[:title]
                    }
                    temp0 = Date.parse(entry[:from])
                    temp1 = Date.parse(entry[:to])
                    while temp0 <= temp1
                        if temp0 >= p && temp0 <= p1
                            holiday_dates << temp0.strftime('%Y-%m-%d')
                        end
                        temp0 += 1
                    end
                end
            end
            @@tage_infos.each do |entry|
                unless (entry[:from] >= p1.strftime('%Y-%m-%d') || entry[:to] < p.strftime('%Y-%m-%d'))
                    holidays << {
                        :start => entry[:from],
                        :end => (Date.parse(entry[:to]) + 1).strftime('%Y-%m-%d'),
                        :title => entry[:title],
                        :label => entry[:title]
                    }
                end
            end
            website_events = []
            Main.get_website_events.each do |entry|
                unless (entry[:date] >= p1.strftime('%Y-%m-%d') || entry[:date] < p.strftime('%Y-%m-%d'))
                    website_events << {
                        :start => entry[:date],
                        :end => (Date.parse(entry[:date]) + 1).strftime('%Y-%m-%d'),
                        :title => entry[:title],
                        :label => entry[:title]
                    }
                end
            end
            # write timetable info for each user (one file per week)
            temp = @@user_info.dup
            @@klassen_order.each do |klasse|
                temp["_#{klasse}"] = {
                    :klasse => klasse,
                    :id => @@klassen_id[klasse]
                }
            end
            temp.each_pair do |email, user|
                lesson_keys = @@lessons_for_user[email].dup
                if email[0] == '_'
                    lesson_keys = Set.new(@@lessons_for_klasse[user[:klasse]])
                end
                lesson_keys ||= Set.new()
                lesson_keys << "_#{user[:klasse]}" unless user[:teacher]
                if user[:teacher]
                    lesson_keys << "_#{user[:shorthand]}" 
                    (@@lessons_for_shorthand[user[:shorthand]] || []).each do |lesson_key|
                        lesson_keys << lesson_key
                    end
                end
                lesson_keys << "_#{user[:email]}"
                next if only_these_lesson_keys && (lesson_keys & only_these_lesson_keys).empty?
#                 unless logged_emails.include?(email)
#                     STDERR.puts email
#                     logged_emails << email
#                 end
                path = "/gen/w/#{user[:id]}/#{p_yw}.json.gz"
                FileUtils.mkpath(File.dirname(path))
                file_count += 1
                Zlib::GzipWriter.open(path) do |f|
                    events = []
                    cache_indices = Set.new()
                    lesson_keys.each do |lesson_key|
                        if (@@user_info[email] || {})[:teacher]
                            cache_indices += ((@lesson_events[lesson_key] || {})[p_yw] || Set.new())
                        else
                            cache_indices += ((@lesson_events[lesson_key] || {})[p_yw] || []).select do |x|
                                @lesson_cache[x][:datum] < regular_events_from
                            end
                            cache_indices += ((@lesson_events_regular[lesson_key] || {})[p_yw] || []).select do |x|
                                @lesson_cache[x][:datum] >= regular_events_from
                            end
                        end
                    end                    
                    events += cache_indices.map { |x| @lesson_cache[x] }
                    events += holidays 
                    events += website_events
                    # add events
                    ((@events_for_user[email] || {})[p_yw] || {}).each_pair do |eid, info|
                        event = info[:event]
                        organized_by = info[:organized_by]
                        if @@user_info[organized_by]
                            organized_by = @@user_info[organized_by][:display_last_name]
                        end
                        event[:start_time] = fix_h_to_hh(event[:start_time])
                        event[:end_time] = fix_h_to_hh(event[:end_time])
                        events << {:lesson => false,
                                   :start => "#{event[:date]}T#{event[:start_time]}",
                                   :end => "#{event[:date]}T#{event[:end_time]}",
                                   :event_title => "#{event[:title]}",
                                   :description => "#{event[:description]}",
                                   :organized_by => organized_by,
                                   :organized_by_email => info[:organized_by],
                                   :eid => event[:id],
                                   :is_event => true,
                                   :room_name => event[:title].gsub(/\s/, '_').gsub(/[^a-zA-Z0-9_]/, '') + '_' + event[:id][0, 8],
                                   :datum => event[:date],
                                   :start_time => event[:start_time],
                                   :end_time => event[:end_time],
                                   :jitsi => event[:jitsi]
                                }
                    end

                    day_message_target = nil
                    if @@user_info[email]
                        if @@user_info[email][:teacher]
                            day_message_target = @@user_info[email][:shorthand]
                        else
                            day_message_target = @@user_info[email][:klasse]
                        end
                    else
                        if email[0] == '_' && KLASSEN_ORDER.include?(email[1, email.size - 1])
                            day_message_target = email[1, email.size- 1]
                        end
                    end

                    ((@@day_messages[p_yw] || {})[day_message_target] || {}).each_pair do |datum, messages|
                        events << {
                            :start => datum,
                            :end => (Date.parse(datum) + 1).strftime('%Y-%m-%d'),
                            :title => messages.join("<br />").gsub("\n", "<br />")
                        }
                    end

                    fixed_events = events.map do |e_old|
                        e = e_old.dup
                        if e[:lesson]
                            e[:label] = user[:teacher] ? e[:label_klasse].dup : e[:label_lehrer].dup
                            e[:label_lang] = user[:teacher] ? e[:label_klasse_lang].dup : e[:label_lehrer_lang].dup
                            e[:label_short] = user[:teacher] ? e[:label_klasse_short].dup : e[:label_lehrer_short].dup
                            if e[:nc_folder]
                                e[:nc_folder] = user[:teacher] ? e[:nc_folder][:teacher].dup : e[:nc_folder][:sus].dup
                            end
                            if e[:nc_collect_folder]
                                e[:nc_collect_folder] = user[:teacher] ? e[:nc_collect_folder][:teacher].dup : e[:nc_collect_folder][:sus].dup
                            end
                            if e[:nc_return_folder]
                                e[:nc_return_folder] = user[:teacher] ? e[:nc_return_folder][:teacher].dup : e[:nc_return_folder][:sus].dup
                            end
                            lesson_key = e[:lesson_key]
                            if e[:lesson] && (lesson_key != 0) && e[:lesson_offset]
                                # 5. add information from database
                                events_with_data_cache[lesson_key] ||= {}
                                unless events_with_data_cache[lesson_key].include?(e[:lesson_offset])
                                    data = {}
                                    [:hausaufgaben_text, :stundenthema_text, :notizen].each do |k|
                                        values = Set.new()
                                        (0...e[:count]).each do |o|
                                            v = (((@lesson_info[lesson_key] || {})[e[:lesson_offset] + o] || {})[:data] || {})[k] || ''
                                            values << v unless v.empty?
                                        end
                                        unless values.empty?
                                            data[k] = values.to_a.join('<br />')
                                        end
                                    end
                                    [:lesson_jitsi, :lesson_nc, :lesson_lr, :homework_nc, :homework_lr, :breakout_rooms_roaming].each do |k|
                                        flag = false
                                        (0...e[:count]).each do |o|
                                            if (((@lesson_info[lesson_key] || {})[e[:lesson_offset] + o] || {})[:data] || {})[k]
                                                flag = true
                                            end
                                        end
                                        if flag
                                            data[k] = true
                                        end
                                    end
                                    [:homework_est_time].each do |k|
                                        sum = 0
                                        (0...e[:count]).each do |o|
                                            v = ((((@lesson_info[lesson_key] || {})[e[:lesson_offset] + o] || {})[:data] || {})[k] || '').strip
                                            sum += v.to_i unless v.empty?
                                        end
                                        if sum > 0
                                            data[k] = sum.to_s
                                        end
                                    end
                                    [:breakout_rooms, :breakout_room_participants].each do |k|
                                        (0...e[:count]).each do |o|
                                            v = (((@lesson_info[lesson_key] || {})[e[:lesson_offset] + o] || {})[:data] || {})[k] || []
                                            if v && (!v.empty?)
                                                data[k] = v
                                            end
                                        end
                                    end
                                    [:booked_tablet].each do |k|
                                        (0...e[:count]).each do |o|
                                            v = (((@lesson_info[lesson_key] || {})[e[:lesson_offset] + o] || {})[:data] || {})[k] || []
                                            if v && (!v.empty?)
                                                tablet_id = v
                                                data[k] = v
                                                tablet_info = @@tablets[tablet_id]
                                                data[:booked_tablet_label_long] = "<span class='tis' style='background-color: #{tablet_info[:bg_color]}; color: #{tablet_info[:fg_color]};'>#{tablet_id}</span> (#{tablet_info[:lagerort]})"
                                                data[:booked_tablet_label_short] = "<span class='tis' style='background-color: #{tablet_info[:bg_color]}; color: #{tablet_info[:fg_color]};'>#{tablet_id}</span>"
                                            end
                                        end
                                    end
                                    [:booked_tablet_sets].each do |k|
                                        (0...e[:count]).each do |o|
                                            v = (((@lesson_info[lesson_key] || {})[e[:lesson_offset] + o] || {})[:data] || {})[k] || []
                                            if v && (!v.empty?)
                                                data[k] = v
                                                # tablet_info = @@tablets[tablet_id]
                                                # data[:booked_tablet_label_long] = "<span class='tis' style='background-color: #{tablet_info[:bg_color]}; color: #{tablet_info[:fg_color]};'>#{tablet_id}</span> (#{tablet_info[:lagerort]})"
                                                # data[:booked_tablet_label_short] = "<span class='tis' style='background-color: #{tablet_info[:bg_color]}; color: #{tablet_info[:fg_color]};'>#{tablet_id}</span>"
                                            end
                                        end
                                    end
                                    [:booked_tablet_sets_total_count].each do |k|
                                        (0...e[:count]).each do |o|
                                            v = (((@lesson_info[lesson_key] || {})[e[:lesson_offset] + o] || {})[:data] || {})[k]
                                            data[k] = v if v
                                        end
                                    end

                                    events_with_data_cache[lesson_key][e[:lesson_offset]] = data
                                end
                                events_with_data_per_user_cache[lesson_key] ||= {}
                                events_with_data_per_user_cache[lesson_key][e[:lesson_offset]] ||= {}
                                unless events_with_data_per_user_cache[lesson_key][e[:lesson_offset]].include?(email)
                                    user_data = {}
                                    (0...e[:count]).each do |o|
                                        comment_info = (((@lesson_info[lesson_key] || {})[e[:lesson_offset] + o] || {})[:comments] || {})[email] || {}
                                        if comment_info[:text_comment]
                                            user_data[:text_comments] ||= []
                                            fach = @@lessons[:lesson_keys][lesson_key][:fach]
                                            fach = @@faecher[fach] if @@faecher[fach]
                                            from = "#{(@@user_info[comment_info[:tcf] || ''] || {})[:display_last_name]} (#{fach})"
                                            user_data[:text_comments] << {
                                                :comment => comment_info[:text_comment], 
                                                :from => from,
                                                :timestamp => comment_info[:timestamp],
                                                :id => comment_info[:id]
                                            }
                                        end
                                    end
                                    (0...e[:count]).each do |o|
                                        comment_info = (((@lesson_info[lesson_key] || {})[e[:lesson_offset] + o] || {})[:comments] || {})[email] || {}
                                        if comment_info[:audio_comment_tag]
                                            user_data[:audio_comments] ||= []
                                            fach = @@lessons[:lesson_keys][lesson_key][:fach]
                                            fach = @@faecher[fach] if @@faecher[fach]
                                            from = "#{(@@user_info[comment_info[:acf] || ''] || {})[:display_last_name]} (#{fach})"
                                            user_data[:audio_comments] << {
                                                :tag => comment_info[:audio_comment_tag], 
                                                :duration => comment_info[:duration], 
                                                :from => from,
                                                :timestamp => comment_info[:timestamp],
                                                :id => comment_info[:id]
                                            }
                                        end
                                    end
                                    # add homework feedback
                                    if user[:teacher]
                                        lesson_homework_feedback[e[:lesson_key]] ||= Main.get_homework_feedback_for_lesson_key(e[:lesson_key])
                                        if lesson_homework_feedback[e[:lesson_key]] && lesson_homework_feedback[e[:lesson_key]][e[:lesson_offset]]
                                            user_data[:homework_feedback] = lesson_homework_feedback[e[:lesson_key]][e[:lesson_offset]]
                                        end
                                    end

                                    events_with_data_per_user_cache[lesson_key][e[:lesson_offset]][email] = user_data
                                end
                                e[:data] = events_with_data_cache[lesson_key][e[:lesson_offset]]
                                e[:per_user] = events_with_data_per_user_cache[lesson_key][e[:lesson_offset]][email]
                            end
                        end
                        e
                    end
                    if user[:teacher]
                        fixed_events.map! do |event|
                            if event[:lesson] && event[:lesson_key]
                                event[:schueler_for_lesson] = (@@schueler_for_lesson[event[:lesson_key]] || []).map do |email|
                                    {:display_name => @@user_info[email][:display_name],
                                     :nc_login => @@user_info[email][:nc_login]
                                    }
                                end
                            end
                            # mark event as entfall FOR THIS PERSON only
                            if event[:lehrer_removed]
                                if event[:lehrer_removed].include?(@@user_info[email][:shorthand])
                                    event[:entfall] = true
                                end
                            end
                            event
                        end
                    end
                    unless user[:teacher]
                        # if it's a schüler, remove pausenaufsichten
                        fixed_events.reject! do |event|
                            event[:pausenaufsicht]
                        end
                        # if it's a schüler, only add events which have the right klasse
                        # (unless it's a phantom event)
                        fixed_events.reject! do |event|
                            if event[:lesson] && (!event[:phantom_event]) && (!event[:pausenaufsicht])
                                !((event[:klassen].first).include?(user[:klasse]) || (event[:klassen].last).include?(user[:klasse]))
                            else
                                false
                            end
                        end
                        # also delete Kurs events for SuS who are not participating in that kurs
                        # (unless it's a phantom event)
                        fixed_events.reject! do |event|
                            if event[:lesson] && (!event[:phantom_event]) && (!event[:pausenaufsicht])
                                if event[:klassen].first.include?('11') || event[:klassen].first.include?('12') || event[:klassen].last.include?('11') || event[:klassen].last.include?('12')
                                    # also handle entfall lessons: check orig_lesson_key first, lesson_key otherwise
                                    check_lesson_key = event[:orig_lesson_key] || event[:lesson_key]
                                    (check_lesson_key != 0) && (@@lessons_for_user[user[:email]]) && (!@@lessons_for_user[user[:email]].include?(check_lesson_key))
                                else
                                    false
                                end
                            else
                                false
                            end
                        end
                        # delete Notizen and booked tablet info for SuS
                        fixed_events.map! do |event|
                            if event[:data]
                                event[:data].delete(:notizen)
                                event[:data].delete(:booked_tablet)
                                event[:data].delete(:booked_tablet_label_long)
                                event[:data].delete(:booked_tablet_label_short)
                                event[:data].delete(:booked_tablet_sets)
                            end
                            event
                        end
                        # unless SuS is permanently at home delete lesson_jitsi flag
                        # in some cases
                        fixed_events.map! do |event|
                            if event[:lesson] && event[:data]
                                unless Main.stream_allowed_for_date_lesson_key_and_email(event[:datum], event[:lesson_key], email, all_stream_restrictions[event[:lesson_key]], all_homeschooling_users.include?(email), group_for_sus[email])
                                    event[:data] = event[:data].reject { |x| x == :lesson_jitsi }
                                end
                            end
                            event
                        end
                        # add schueler_offset_in_lesson for SuS
                        fixed_events.map! do |event|
                            if event[:lesson_key]
                                event[:schueler_offset_in_lesson] = (@@schueler_offset_in_lesson[event[:lesson_key]] || {})[user[:email]] || 0
                            end
                            event
                        end
                        # add future homework for SuS
                        fixed_events.map! do |_event|
                            # TODO: this code can't work because we're using symbols from parsed JSON
                            # but it's kind of okay because we don't need homework in the lesson modal
                            event = JSON.parse(_event.to_json)
                            if (all_homework[event[:lesson_key]] || {})[event[:datum]]
                                all_homework[event[:lesson_key]][event[:datum]].each_pair do |k, v|
#                                                 [:hausaufgaben_text, :homework_nc, :homework_lr].each do |k|
                                    if [:homework_nc, :homework_lr].include?(k)
                                        event[:data][k] = (event[:data][k] || false) || v
                                    elsif k == :hausaufgaben_text
                                        parts = []
                                        parts << event[:data][k] if event[:data][k]
                                        parts << v
                                        event[:data][k] = parts.join('<br />').strip
                                    elsif k == :homework_est_time
                                        parts = []
                                        parts << event[:data][k] if event[:data][k]
                                        parts << v
                                        event[:data][k] = (parts.map { |x| x.to_i }.sum).to_s
                                    end
                                end
                            end
                            event
                        end
                        fixed_events.map! do |event|
                            # mark event as entfall FOR THIS PERSON only
                            if event[:klassen_removed]
                                if event[:klassen_removed].include?(@@user_info[email][:klasse])
                                    event[:entfall] = true
                                end
                            end
                            event
                        end
                    end
                    write_events = fixed_events.reject { |x| x[:deleted] || x['deleted']}
                    f.print({:events => write_events, 
                             :vplan_timestamp => @@vplan_timestamp,
                             :switch_week => Main.get_switch_week_for_date(p)}.to_json)
                    if only_these_lesson_keys.nil? && email[0] != '_'
                        write_events.each do |event|
                            # re-parse because keys are strings for SuS and symbols for LuL (?)
                            event = JSON.parse(event.to_json)
                            next if event['start'][0, 10] < Date.today.strftime('%Y-%m-%d')

                            key = nil
                            date = nil
                            tstart = nil
                            tend = nil
                            if event['lesson']
                                if (event['data'] || {})['lesson_jitsi']
                                    key = "#{event['lesson_key']}/#{event['lesson_offset']}"
                                    date = event['start'][0, 10]
                                    tstart = event['start'][11, 5]
                                    tend = event['end'][11, 5]
                                end
                            elsif event['is_event']
                                if event['jitsi']
                                    key = "#{event['eid']}"
                                    date = event['start'][0, 10]
                                    tstart = event['start'][11, 5]
                                    tend = event['end'][11, 5]
                                end
                            end
                            if key
                                jitsi_count_for_dh[date] ||= {}
                                jitsi_count_for_dh[date][key] ||= {:start => tstart, :end => tend, :count => 0}
                                jitsi_count_for_dh[date][key][:count] += 1
                            end
                        end
                    end

                    if ical_tokens[email]
                        ical_events[email] ||= []
                        write_events.each do |event|
                            STDERR.puts event.keys.to_json
                            event_str = StringIO.open do |io|
                                if event[:is_event]
                                    io.puts "BEGIN:VEVENT"
                                    io.puts "DTSTART;TZID=Europe/Berlin:#{event[:start].gsub('-', '').gsub(':', '')}00"
                                    io.puts "DTEND;TZID=Europe/Berlin:#{event[:end].gsub('-', '').gsub(':', '')}00"
                                    io.puts "SUMMARY:#{fix_label_for_unicode(event[:event_title])}"
                                    io.puts "DESCRIPTION:#{event[:description].gsub("\n", "\\n")}"
                                    io.puts "END:VEVENT"
                                end
                                next if event[:label].nil?
                                io.puts "BEGIN:VEVENT"
                                io.puts "DTSTART;TZID=Europe/Berlin:#{event[:start].gsub('-', '').gsub(':', '')}00"
                                io.puts "DTEND;TZID=Europe/Berlin:#{event[:end].gsub('-', '').gsub(':', '')}00"
                                io.puts "SUMMARY:#{fix_label_for_unicode(event[:label])}"
                                temp = StringIO.open do |io2|
                                    data = event[:data] || {}
                                    if data[:stundenthema_text]
                                        io2.puts data[:stundenthema_text]
                                        io2.puts
                                    end
                                    if data[:lesson_jitsi] || data[:lesson_nc] || data[:lesson_lr]
                                        options = []
                                        options << 'Jitsi' if data[:lesson_jitsi]
                                        options << 'Nextcloud' if data[:lesson_nc]
                                        options << 'Lernraum' if data[:lesson_lr]
                                        io2.puts "Die Stunde wird per #{options.join(' / ')} durchgeführt."
                                        io2.puts
                                    end
                                    if data[:notizen]
                                        io2.puts data[:notizen]
                                        io2.puts
                                    end
                                    if data[:hausaufgaben_text] || data[:homework_nc] || data[:homework_lr]
                                        options = []
                                        options << 'Nextcloud' if data[:homework_nc]
                                        options << 'Lernraum' if data[:homework_lr]
                                        options_label = ''
                                        options_label = " (#{options.join(' / ')})" unless options.empty?
                                        io2.print "Hausaufgaben#{options_label}"
                                        if data[:hausaufgaben_text]
                                            io2.print ': '
                                            io2.puts data[:hausaufgaben_text]
                                        else
                                            io2.puts
                                        end
                                        io2.puts
                                    end
                                    io2.string.strip
                                end
                                unless temp.empty?
                                    io.puts "DESCRIPTION:#{temp.gsub("\n", "\\n")}"
                                end
#                                 io.puts "UID:#{tag}-#{event[:tag]}"
                                io.puts "END:VEVENT"
                                io.string.strip
                            end
                            ical_events[email] << event_str unless event_str.nil?
                        end
                    end
                end
            end
            p += 7
        end
        ical_events.each_pair do |email, events|
            FileUtils::mkpath('/gen/ical')
            File.open("/gen/ical/#{ical_tokens[email]}.ics", 'w') do |f|
                f.puts "BEGIN:VCALENDAR"
                f.puts "VERSION:2.0"
                f.puts "CALSCALE:GREGORIAN"
                f.puts "X-WR-CALNAME:Dashboard #{SCHUL_NAME}"
                events.each do |e| 
                    x = e.strip
                    f.puts x unless x.empty?
                end
                f.puts "END:VCALENDAR"
            end
        end
        if only_these_lesson_keys.nil?
            File.open('/gen/jitsi_projection.json', 'w') do |f|
                f.write(jitsi_count_for_dh.to_json)
            end
        end
        
        holidays = []
        @@ferien_feiertage.each do |entry|
            unless (entry[:to] < @@config[:first_day] || entry[:from] > @@config[:last_day])
                holidays << {
                    :start => entry[:from],
                    :end => Date.parse(entry[:to]).strftime('%Y-%m-%d'),
                    :title => entry[:title]
                }
            end
        end
        @@tage_infos.each do |entry|
            unless (entry[:to] < @@config[:first_day] || entry[:from] > @@config[:last_day])
                holidays << {
                    :start => entry[:from],
                    :end => Date.parse(entry[:to]).strftime('%Y-%m-%d'),
                    :title => entry[:title]
                }
            end
        end
        # write timetable info for each lesson series (entire time range: all.json.gz)
        @lesson_events.each_pair do |lesson_key, levents|
            next if only_these_lesson_keys && (!only_these_lesson_keys.include?(lesson_key))
            lesson_info = @@lessons[:lesson_keys][lesson_key]
            next if lesson_info.nil?
            path = "/gen/w/#{lesson_info[:id]}/all.json.gz"
            FileUtils.mkpath(File.dirname(path))
            Zlib::GzipWriter.open(path) do |f|
                events = []
                events += holidays 
                levents.keys.sort.each do |yw|
                    events += levents[yw].map { |x| @lesson_cache[x] }
                end
                events.sort! do |a, b|
                    "#{a[:datum] || a[:start]}/#{a[:stunde]}" <=> "#{b[:datum] || b[:start]}/#{b[:stunde]}"
                end
                events.map! do |e|
                    e[:label] = e[:label_klasse_short].dup
                    e
                end
                f.print(events.reject { |x| x[:deleted] }.to_json)
            end
        end
        # write messages for each user
        @@user_info.each_pair do |email, user|
            lesson_keys = @@lessons_for_user[email].dup
            lesson_keys ||= Set.new()
            lesson_keys << "_#{user[:klasse]}" unless user[:teacher]
            lesson_keys << "_#{user[:shorthand]}" if user[:teacher]
            if only_these_lesson_keys && (lesson_keys & only_these_lesson_keys).empty?
                unless only_these_lesson_keys.include?(:all_messages) || only_these_lesson_keys.include?(:event)
                    next 
                end
            end
            path = "/gen/w/#{user[:id]}/messages.json.gz"
            FileUtils.mkpath(File.dirname(path))
            Zlib::GzipWriter.open(path) do |f|
                messages = []
                (@text_comments_for_user[email] || {}).each_pair do |lesson_key, e0|
                    e0.each_pair do |offset, e1|
                        messages << e1
                        messages.last[:lesson_key] = lesson_key
                    end
                end
                (@audio_comments_for_user[email] || {}).each_pair do |lesson_key, e0|
                    e0.each_pair do |offset, e1|
                        messages << e1
                        messages.last[:lesson_key] = lesson_key
                    end
                end
                (@messages_for_user[email] || {}).each_pair do |mid, info|
                    messages << {:mid => mid, :timestamp => info[:timestamp], :from => info[:from] }
                end
                messages.sort! do |a, b|
                    b[:timestamp] <=> a[:timestamp]
                end
                messages.map! do |x|
                    t = Time.at(x[:timestamp])
                    x[:date] = t.strftime('%Y-%m-%d')
                    x[:dow] = t.wday
                    x[:from_email] = x[:from]
                    x[:from] = "#{(@@user_info[x[:from]] || {})[:display_name] || x[:from]}"
                    x
                end
                f.print(messages.to_json)
            end
        end
        # write homework for each user
        temp = @@user_info.dup
        @@klassen_order.each do |klasse|
            temp["_#{klasse}"] = {
                :klasse => klasse,
                :id => @@klassen_id[klasse]
            }
        end
        temp.each_pair do |email, user|
            lesson_keys = @@lessons_for_user[email].dup
            if email[0] == '_'
                lesson_keys = Set.new(@@lessons_for_klasse[user[:klasse]])
            end
            lesson_keys ||= Set.new()
            lesson_keys << "_#{user[:klasse]}" unless user[:teacher]
            lesson_keys << "_#{user[:shorthand]}" if user[:teacher]
            if only_these_lesson_keys && (lesson_keys & only_these_lesson_keys).empty?
                unless only_these_lesson_keys.include?(:all_messages) || only_these_lesson_keys.include?(:event)
                    next 
                end
            end
            path = "/gen/w/#{user[:id]}/homework.json.gz"
            FileUtils.mkpath(File.dirname(path))
            Zlib::GzipWriter.open(path) do |f|
                homework = {}
                lesson_keys.each do |lesson_key|
                    (all_homework[lesson_key] || {}).keys.sort.each do |datum|
                        next if datum < today_date || datum >= today_plus_7_days
                        homework[datum] ||= []
                        homework[datum] << {:lesson_key => lesson_key, :info => all_homework[lesson_key][datum]}
                    end
                end
                chronological_homework = []
                homework.keys.sort.each do |datum|
                    homework[datum].each do |entry|
                        fach = @@lessons[:lesson_keys][entry[:lesson_key]][:fach]
                        fach = @@faecher[fach] if @@faecher[fach]
                        if user[:teacher]
                            klassen = @@lessons[:lesson_keys][entry[:lesson_key]][:klassen]
                            fach = "#{fach} (#{klassen.sort.map { |x| Main.tr_klasse(x) }.join(', ')})"
                        end
                        lehrer = @@lessons[:lesson_keys][entry[:lesson_key]][:lehrer]
                        if entry[:info]
                            homework_text = []
                            homework_text << entry[:info][:hausaufgaben_text] if entry[:info][:hausaufgaben_text]
                            homework_text << "Es befinden sich Hausaufgaben in der Nextcloud." if entry[:info][:homework_nc]
                            homework_text << "Es befinden sich Hausaufgaben im Lernraum." if entry[:info][:homework_lr]
                            chronological_homework << {
                                :datum => datum, 
                                :text => homework_text, 
                                :fach => fach,
                                :lehrer => lehrer.map { |x| (@@user_info[@@shorthands[x]] || {})[:display_last_name]}.join(', '),
                                :est_time => entry[:info][:homework_est_time].to_i,
                                :lesson_key => entry[:lesson_key],
                                :offset => entry[:info][:offset],
                            }
                        end
                    end
                end
                f.print(chronological_homework.to_json)
            end
        end
        STDERR.puts
        return file_count
    end
    
    def update_recipients(only_this_email = nil)
        debug "Updating recipients"
        # write recipients for each user
        group_for_sus = {}
        results = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User)
            RETURN u.email, COALESCE(u.group2, 'A') AS group2;
        END_OF_QUERY
        results.each do |x|
            group_for_sus[x['u.email']] = x['group2']
        end
        groups_for_user = {}
        users_with_defined_groups = nil
        if only_this_email
            users_with_defined_groups = [only_this_email]
        else
            users_with_defined_groups = neo4j_query(<<~END_OF_QUERY).map { |x| x['ou.email'] }
                MATCH (g:Group)-[:DEFINED_BY]->(ou:User)
                WHERE COALESCE(g.deleted, false) = false
                WITH g, ou
                RETURN DISTINCT ou.email;
            END_OF_QUERY
        end
        # debug users_with_defined_groups.to_yaml
        stored_groups = neo4j_query(<<~END_OF_QUERY, {:emails => users_with_defined_groups}).map { |x| {:email => x['ou.email'], :info => x['g'].props, :recipient => x['u.email']} }
            MATCH (g:Group)-[:DEFINED_BY]->(ou:User)
            WHERE COALESCE(g.deleted, false) = false
            AND ou.email IN {emails}
            WITH g, ou
            OPTIONAL MATCH (u)-[r:IS_PART_OF]->(g)
            WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(r.deleted, false) = false
            RETURN g, u.email, ou.email
            ORDER BY g.created DESC, g.id;
        END_OF_QUERY
        # debug stored_groups.to_yaml
        stored_groups.each do |x|
            groups_for_user[x[:email]] ||= {}
            groups_for_user[x[:email]][x[:info][:id]] ||= { :name => x[:info][:name], :recipients => []}
            groups_for_user[x[:email]][x[:info][:id]][:recipients] << x[:recipient]
        end
        # debug groups_for_user.to_yaml

        @@user_info.each_pair do |email, user|
            next if only_this_email && only_this_email != email
            next unless user[:teacher] || user[:sv]
            path = "/gen/w/#{user[:id]}/recipients.json.gz"
            FileUtils.mkpath(File.dirname(path))
            Zlib::GzipWriter.open(path) do |f|
                recipients = {}
                klassen = @@klassen_order
                klassen.each do |klasse|
                    recipients["/klasse/#{klasse}"] = {:label => "Klasse #{klasse}",
                                                       :entries => @@schueler_for_klasse[klasse]
                                                       }
                    groups_for_klasse = Set.new()
                    (@@schueler_for_klasse[klasse] || []).each do |email|
                        if group_for_sus[email]
                            groups_for_klasse << group_for_sus[email]
                        end
                    end
                    if groups_for_klasse.size > 1
                        groups_for_klasse.each do |group|
                            recipients["/klasse/#{klasse}/#{group}"] = 
                                    {:label => "Klasse #{klasse} (Gruppe #{group})",
                                     :entries => @@schueler_for_klasse[klasse].select { |email| group_for_sus[email] == group }
                                    }
                        end
                    end
                    teacher_emails = []
                    (@@teachers_for_klasse[klasse] || {}).keys.each do |shorthand|
                        next unless @@shorthands[shorthand]
                        teacher_emails << @@user_info[@@shorthands[shorthand]][:email]
                    end
                    recipients["/klasse/#{klasse}/lehrer"] = 
                            {:label => "Lehrer der Klasse #{klasse}",
                             :entries => teacher_emails
                            }
                end
                klassen.each do |klasse|
                    (@@schueler_for_klasse[klasse] || []).each do |email|
                        recipients[email] = {:label => @@user_info[email][:display_name]}
                    end
                end
                if user[:teacher]
                    @@user_info.each_pair do |email, user|
                        next unless user[:teacher]
                        recipients[email] = {:label => @@user_info[email][:display_name],
                                             :teacher => true}
                    end
                end
                if user[:teacher] || user[:sv]
                    recipients['/schueler/*'] = {:label => 'Gesamte Schülerschaft',
                                                 :entries => @@user_info.select { |k, v| !v[:teacher]}.map { |k, v| k }}
                end
                if user[:can_see_all_timetables]
                    recipients['/eltern/*'] = {:label => 'Gesamte Elternschaft',
                                               :entries => @@user_info.select { |k, v| !v[:teacher]}.map { |k, v| 'eltern.' + k }}
                end
                if user[:teacher]
                    recipients['/lehrer/*'] = {:label => 'Gesamtes Kollegium',
                                               :teacher => true,
                                               :entries => @@user_info.select { |k, v| v[:teacher]}.map { |k, v| k }}
                end
                (groups_for_user[email] || {}).each_pair do |gid, g|
                    recipients["/custom/#{gid}"] = {:label => g[:name], :entries => g[:recipients]}
                end

                groups = recipients.keys.select do |key|
                    recipients[key].include?(:entries)
                end.sort do |a, b|
                    (recipients[b][:entries] || []).size <=> (recipients[a][:entries] || []).size
                end
                data = {:recipients => recipients, :groups => groups}
                f.print(data.to_json)
            end
        end
    end
    
    def update(only_these_lesson_keys)
        if only_these_lesson_keys.nil?
            update_timetables()
            update_recipients()
        end
        
        add_these_lesson_keys = Set.new()
        
        @lesson_info ||= {}
        @text_comments_for_user ||= {}
        @audio_comments_for_user ||= {}
        @messages_for_user ||= {}
        @events_for_user ||= {}
        @lesson_info_last_timestamp ||= 0
        fetched_lesson_info_count = 0
        fetched_text_comments_count = 0
        fetched_audio_comments_count = 0
        fetched_message_count = 0
        # refresh lesson info from database
        # first delete all info entries which are not present anymore
        (only_these_lesson_keys || []).each do |lesson_key|
            if @lesson_info[lesson_key]
                present_offsets = neo4j_query(<<~END_OF_QUERY, {:lesson_key => lesson_key}).map { |x| x['i.offset'] }
                    MATCH (i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: {lesson_key}})
                    RETURN i.offset;
                END_OF_QUERY
                present_offsets = Set.new(present_offsets)
                @lesson_info[lesson_key].select! do |offset, info|
                    present_offsets.include?(offset)
                end
            elsif lesson_key =~ /^_event_/
                event_id = lesson_key.sub('_event_', '')
                rows = neo4j_query(<<~END_OF_QUERY, {:eid => event_id}).map { |x| x['u.email'] }
                    MATCH (u:User)-[:IS_PARTICIPANT]->(e:Event {id: {eid}})
                    RETURN u.email;
                END_OF_QUERY
                rows.each do |email|
                    add_these_lesson_keys << "_#{email}"
                end
                ou_email = neo4j_query_expect_one(<<~END_OF_QUERY, {:eid => event_id})['u.email']
                    MATCH (e:Event {id: {eid}})-[:ORGANIZED_BY]->(u:User)
                    RETURN u.email;
                END_OF_QUERY
                add_these_lesson_keys << "_#{ou_email}"
            elsif lesson_key =~ /^_poll_run_/
                poll_run_id = lesson_key.sub('_poll_run_', '')
                rows = neo4j_query(<<~END_OF_QUERY, {:prid => poll_run_id}).map { |x| x['u.email'] }
                    MATCH (u:User)-[:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})
                    RETURN u.email;
                END_OF_QUERY
                rows.each do |email|
                    add_these_lesson_keys << "_#{email}"
                end
                ou_email = neo4j_query_expect_one(<<~END_OF_QUERY, {:prid => poll_run_id})['u.email']
                    MATCH (pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(u:User)
                    RETURN u.email;
                END_OF_QUERY
                add_these_lesson_keys << "_#{ou_email}"
            elsif lesson_key =~ /^_groups_/
                email = lesson_key.sub('_groups_/', '')
                update_recipients(email)
            end
        end
        # now fetch all updated info nodes with booked tablet sets
        rows = neo4j_query(<<~END_OF_QUERY, {:ts => @lesson_info_last_timestamp}).map { |x| {:info => x['i'].props, :key => x['key'], :tablet_set_id => x['tablet_set_id'] } }
            MATCH (t:TabletSet)<-[:BOOKED]-(b:Booking)-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            WHERE i.updated >= {ts}
            RETURN i, l.key AS key, t.id AS tablet_set_id;
        END_OF_QUERY
        updated_booked_tablet_sets_for_lesson_key_and_offset = {}
        rows.each do |row|
            updated_booked_tablet_sets_for_lesson_key_and_offset[row[:key]] ||= {}
            updated_booked_tablet_sets_for_lesson_key_and_offset[row[:key]][row[:info][:offset]] ||= []
            updated_booked_tablet_sets_for_lesson_key_and_offset[row[:key]][row[:info][:offset]] << row[:tablet_set_id]
        end
        # now fetch all updated info nodes
        rows = neo4j_query(<<~END_OF_QUERY, {:ts => @lesson_info_last_timestamp}).map { |x| {:info => x['i'].props, :key => x['key'], :tablet_id => x['tablet_id'] } }
            MATCH (i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            WHERE i.updated >= {ts}
            WITH i, l
            OPTIONAL MATCH (t:Tablet)<-[:WHICH]-(b:Booking {confirmed: true})-[:FOR]->(i)
            RETURN i, l.key AS key, t.id AS tablet_id;
        END_OF_QUERY
        fetched_lesson_info_count = rows.size
        rows.each do |row|
            @lesson_info[row[:key]] ||= {}
            @lesson_info_last_timestamp = row[:info][:updated] if row[:info][:updated] > @lesson_info_last_timestamp
            h = row[:info].reject do |k, v|
                [:offset, :updated].include?(k)
            end
            @lesson_info[row[:key]][row[:info][:offset]] ||= {}
            @lesson_info[row[:key]][row[:info][:offset]][:data] = h
            if row[:tablet_id]
                tablet_info = @@tablets[row[:tablet_id]]
                @lesson_info[row[:key]][row[:info][:offset]][:data][:booked_tablet] = row[:tablet_id]
            end
            tablet_set_ids = (updated_booked_tablet_sets_for_lesson_key_and_offset[row[:key]] || {})[row[:info][:offset]]
            if tablet_set_ids
                tablet_set_ids.sort! 
                @lesson_info[row[:key]][row[:info][:offset]][:data][:booked_tablet_sets] = tablet_set_ids
                @lesson_info[row[:key]][row[:info][:offset]][:data][:booked_tablet_sets_total_count] = tablet_set_ids.inject(0) { |sum, x| sum + ((@@tablet_sets[x] || {}) [:count] || 0)}
            end
        end
        # refresh text comments from database
        @text_comments_last_timestamp ||= 0
        rows = neo4j_query(<<~END_OF_QUERY, {:ts => @text_comments_last_timestamp}).map { |x| {:info => x['c'].props, :key => x['key'], :schueler => x['s.email'], :tcf => x['tcf.email'] } }
            MATCH (s:User)<-[:TO]-(c:TextComment)-[:BELONGS_TO]->(l:Lesson)
            WHERE c.updated >= {ts}
            WITH s, c, l
            OPTIONAL MATCH (c)-[:FROM]->(tcf:User)
            RETURN c, l.key AS key, s.email, tcf.email;
        END_OF_QUERY
        fetched_text_comments_count = rows.size
        rows.each do |row|
            @lesson_info[row[:key]] ||= {}
            @text_comments_last_timestamp = row[:info][:updated] if row[:info][:updated] > @text_comments_last_timestamp
            @lesson_info[row[:key]][row[:info][:offset]] ||= {}
            @lesson_info[row[:key]][row[:info][:offset]][:comments] ||= {}
            @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]] ||= {}
            @text_comments_for_user[row[:schueler]] ||= {}
            @text_comments_for_user[row[:schueler]][row[:key]] ||= {}
            if row[:info][:comment]
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]][:text_comment] = row[:info][:comment]
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]][:tcf] = row[:tcf]
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]][:timestamp] = row[:info][:updated]
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]][:id] = row[:info][:id]
                @text_comments_for_user[row[:schueler]][row[:key]][row[:info][:offset]] ||= {}
                @text_comments_for_user[row[:schueler]][row[:key]][row[:info][:offset]][:text_comment] = row[:info][:comment]
                @text_comments_for_user[row[:schueler]][row[:key]][row[:info][:offset]][:from] = row[:tcf]
                @text_comments_for_user[row[:schueler]][row[:key]][row[:info][:offset]][:timestamp] = row[:info][:updated]
                @text_comments_for_user[row[:schueler]][row[:key]][row[:info][:offset]][:id] = row[:info][:id]
            else
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]].delete(:text_comment)
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]].delete(:tcf)
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]].delete(:timestamp)
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]].delete(:id)
                @text_comments_for_user[row[:schueler]][row[:key]].delete(row[:info][:offset])
                if @text_comments_for_user[row[:schueler]][row[:key]].empty?
                    @text_comments_for_user[row[:schueler]].delete(row[:key])
                end
            end
        end
        # refresh audio comments from database
        @audio_comments_last_timestamp ||= 0
        rows = neo4j_query(<<~END_OF_QUERY, {:ts => @audio_comments_last_timestamp}).map { |x| {:info => x['c'].props, :key => x['key'], :schueler => x['s.email'], :acf => x['acf.email'] } }
            MATCH (s:User)<-[:TO]-(c:AudioComment)-[:BELONGS_TO]->(l:Lesson)
            WHERE c.updated >= {ts}
            WITH s, c, l
            OPTIONAL MATCH (c)-[:FROM]->(acf:User)
            RETURN c, l.key AS key, s.email, acf.email;
        END_OF_QUERY
        fetched_audio_comments_count = rows.size
        rows.each do |row|
            @lesson_info[row[:key]] ||= {}
            @audio_comments_last_timestamp = row[:info][:updated] if row[:info][:updated] > @audio_comments_last_timestamp
            @lesson_info[row[:key]][row[:info][:offset]] ||= {}
            @lesson_info[row[:key]][row[:info][:offset]][:comments] ||= {}
            @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]] ||= {}
            @audio_comments_for_user[row[:schueler]] ||= {}
            @audio_comments_for_user[row[:schueler]][row[:key]] ||= {}
            if row[:info][:tag]
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]][:audio_comment_tag] = row[:info][:tag]
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]][:duration] = row[:info][:duration]
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]][:acf] = row[:acf]
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]][:timestamp] = row[:info][:updated]
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]][:id] = row[:info][:id]
                @audio_comments_for_user[row[:schueler]][row[:key]][row[:info][:offset]] ||= {}
                @audio_comments_for_user[row[:schueler]][row[:key]][row[:info][:offset]][:audio_comment_tag] = row[:info][:tag]
                @audio_comments_for_user[row[:schueler]][row[:key]][row[:info][:offset]][:duration] = row[:info][:duration]
                @audio_comments_for_user[row[:schueler]][row[:key]][row[:info][:offset]][:from] = row[:acf]
                @audio_comments_for_user[row[:schueler]][row[:key]][row[:info][:offset]][:timestamp] = row[:info][:updated]
                @audio_comments_for_user[row[:schueler]][row[:key]][row[:info][:offset]][:id] = row[:info][:id]
            else
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]].delete(:audio_comment_tag)
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]].delete(:duration)
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]].delete(:acf)
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]].delete(:timestamp)
                @lesson_info[row[:key]][row[:info][:offset]][:comments][row[:schueler]].delete(:id)
                @audio_comments_for_user[row[:schueler]][row[:key]].delete(row[:info][:offset])
                if @audio_comments_for_user[row[:schueler]][row[:key]].empty?
                    @audio_comments_for_user[row[:schueler]].delete(row[:key])
                end
            end
        end
        # refresh messages from database
        @messages_last_timestamp ||= 0
        rows = neo4j_query(<<~END_OF_QUERY, {:ts => @messages_last_timestamp}).map { |x| {:info => x['m'].props, :from => x['mf.email'], :to => x['u.email'], :rt => x['rt'].props } }
            MATCH (u:User)<-[rt:TO]-(m:Message)-[:FROM]->(mf:User)
            WHERE m.updated >= {ts} OR rt.updated >= {ts}
            RETURN m, mf.email, u.email, rt
            ORDER BY m.created DESC
        END_OF_QUERY
        fetched_message_count = rows.size
        rows.each do |row|
            @messages_for_user[row[:to]] ||= {}
            @messages_last_timestamp = row[:info][:updated] if row[:info][:updated] > @messages_last_timestamp
            if (row[:rt] || {})[:updated]
                @messages_last_timestamp = row[:rt][:updated] if row[:rt][:updated] > @messages_last_timestamp
            end
            if row[:info][:id] && !row[:info][:deleted] && !(row[:rt] || {})[:deleted]
                @messages_for_user[row[:to]][row[:info][:id]] = {
                    :timestamp => row[:info][:created],
                    :from => row[:from]
                }
            else
                @messages_for_user[row[:to]].delete(row[:info][:id])
            end
        end
        # refresh events from database
        @events_last_timestamp ||= 0
        rows = neo4j_query(<<~END_OF_QUERY, {:ts => @events_last_timestamp}).map { |x| {:info => x['e'].props, :organized_by => x['ou.email'] } }
            MATCH (e:Event)-[:ORGANIZED_BY]->(ou:User)
            WHERE e.updated >= {ts}
            RETURN e, ou.email
            ORDER BY e.created DESC
        END_OF_QUERY
        fetched_event_count = rows.size
        eids = Set.new()
        rows.each do |row|
            eids << row[:info][:id]
        end
        temp = neo4j_query(<<~END_OF_QUERY, {:eids => eids.to_a.sort}).map { |x| {:eid => x['e.id'], :participant => x['u.email'], :rt => x['rt'].props } }
            MATCH (u:User)-[rt:IS_PARTICIPANT]->(e:Event)
            WHERE e.id IN {eids}
            RETURN e.id, u.email, rt
        END_OF_QUERY
        all_prows = {}
        temp.each do |entry|
            all_prows[entry[:eid]] ||= []
            all_prows[entry[:eid]] << {:participant => entry[:participant],
                                       :rt => entry[:rt]}
        end
        rows.each do |row|
            ds_date = Date.parse(row[:info][:date])
            ds_yw = ds_date.strftime('%Y-%V')
            # add event to organizer's events
            if row[:info][:id] && !row[:info][:deleted]
                @events_for_user[row[:organized_by]] ||= {}
                @events_for_user[row[:organized_by]][ds_yw] ||= {}
                @events_for_user[row[:organized_by]][ds_yw][row[:info][:id]] = {
                    :event => row[:info],
                    :organized_by => row[:organized_by]
                }
            else
                if @events_for_user[row[:organized_by]] && @events_for_user[row[:organized_by]][ds_yw]
                    @events_for_user[row[:organized_by]][ds_yw].delete(row[:info][:id])
                end
            end
            prows = all_prows[row[:info][:id]] || []
            prows.each do |prow|
                @events_for_user[prow[:participant]] ||= {}
                @events_last_timestamp = row[:info][:updated] if row[:info][:updated] > @events_last_timestamp
                if (prow[:rt] || {})[:updated]
                    @events_last_timestamp = prow[:rt][:updated] if prow[:rt][:updated] > @events_last_timestamp
                end
                if row[:info][:id] && !row[:info][:deleted] && !(prow[:rt] || {})[:deleted]
                    @events_for_user[prow[:participant]][ds_yw] ||= {}
                    @events_for_user[prow[:participant]][ds_yw][row[:info][:id]] = {
                        :event => row[:info],
                        :organized_by => row[:organized_by]
                    }
                else
                    if @events_for_user[prow[:participant]][ds_yw]
                        @events_for_user[prow[:participant]][ds_yw].delete(row[:info][:id])
                    end
                end
            end
        end
        debug "Fetched #{fetched_lesson_info_count} updated lesson events, #{fetched_text_comments_count} updated text comments, #{fetched_audio_comments_count} updated audio comments, #{fetched_message_count} updated messages and #{fetched_event_count} updated events."
        
        unless add_these_lesson_keys.empty?
            only_these_lesson_keys = (only_these_lesson_keys || Set.new()) | add_these_lesson_keys
        end
        return update_weeks(only_these_lesson_keys)
    end
end
