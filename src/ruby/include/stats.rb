class Main < Sinatra::Base
    def get_login_stats
        login_seen = {}
        LOGIN_STATS_D.each do |d|
            login_counts = neo4j_query(<<~END_OF_QUERY, :today => (Date.today - d).to_s)
                MATCH (u:User) WHERE EXISTS(u.last_access) AND u.last_access >= {today}
                RETURN u.email;
            END_OF_QUERY
            login_counts.map { |x| x['u.email'] }.each do |email|
                login_seen[email] ||= {}
                login_seen[email][d] = true
            end
        end
        login_stats = {}
        @@klassen_order.each do |klasse|
            login_stats[klasse] = {:total => (@@schueler_for_klasse[klasse] || []).size, :count => {}}
        end
        teacher_count = 0
        sus_count = 0
        @@user_info.each_pair do |email, user|
            if user[:teacher]
                teacher_count += 1 
            else
                sus_count += 1 
            end
        end
        login_stats[:lehrer] = {:total => teacher_count, :count => {}}
        login_stats[:sus] = {:total => sus_count, :count => {}}
        login_seen.each_pair do |email, seen|
            user = @@user_info[email]
            next if user.nil?
            seen.keys.each do |d|
                if user[:teacher]
                    login_stats[:lehrer][:count][d] ||= 0
                    login_stats[:lehrer][:count][d] += 1
                else
                    login_stats[:sus][:count][d] ||= 0
                    login_stats[:sus][:count][d] += 1
                    if login_stats[user[:klasse]]
                        login_stats[user[:klasse]][:count][d] ||= 0
                        login_stats[user[:klasse]][:count][d] += 1
                    end
                end
            end
        end
        login_stats
    end
    
    def print_stats()
        require_admin!
        login_stats = get_login_stats()
        StringIO.open do |io|
            io.puts "<table class='table table-narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Gruppe</th>"
            io.puts "<th>jemals</th>"
            io.puts "<th>letzte 4 Wochen</th>"
            io.puts "<th>letzte Woche</th>"
            io.puts "<th>heute</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            ([:sus, :lehrer] + @@klassen_order).each do |key|
                label = nil
                if key == :sus
                    label = 'Schülerinnen und Schüler'
                elsif key == :lehrer
                    label = 'Lehrerinnen und Lehrer'
                else
                    label = "Klasse #{tr_klasse(key)}" 
                end
                io.puts "<tr>"
                io.puts "<td>#{label}</td>"
                LOGIN_STATS_D.reverse.each do |d|
                    io.puts "<td>"
                    data = login_stats[key]
                    percent = data[:total] == 0 ? 0 : ((data[:count][d] || 0) * 100 / data[:total]).to_i
                    bgcol = get_gradient(['#cc0000', '#f4951b', '#ffe617', '#80bc42'], percent / 100.0)
                    io.puts "<span style='background-color: #{bgcol}; padding: 4px 8px; margin: 0; border-radius: 3px;'>#{percent}%</span>"
                    io.puts "</td>"
                end
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.string
        end
    end
    
    def print_login_ranking()
        stats = get_login_stats()
        klassen_stats = {}
        @@klassen_order.each do |klasse|
            klassen_stats[klasse] = 100 * stats[klasse][:count][LOGIN_STATS_D.last].to_f / stats[klasse][:total]
            if stats[klasse][:count][LOGIN_STATS_D.last] == stats[klasse][:total]
                neo4j_query(<<~END_OF_QUERY, :klasse => klasse, :timestamp => Time.now.to_i)
                    MERGE (n:KlasseKomplett {klasse: {klasse}})
                    ON CREATE SET n.timestamp = {timestamp}
                END_OF_QUERY
            end
        end
        klassen_ranking = neo4j_query(<<~END_OF_QUERY).map { |x| x['n.klasse'] }
            MERGE (n:KlasseKomplett)
            RETURN n.klasse
            ORDER BY n.timestamp ASC;
        END_OF_QUERY
        now = Time.now.to_i
        StringIO.open do |io|
            io.puts "<p style='text-align: center;'>"
            io.puts "<em>Die ersten Klassen sind komplett im Dashboard angemeldet.<br />Herzlichen Glückwunsch an die Klassen #{join_with_sep(klassen_ranking.map { |x| '<b>' + (tr_klasse(x) || '') + '</b>' }, ', ', ' und ')}!</em>"
            io.puts "</p>"
            klassen_stats.keys.sort do |a, b|
                va = sprintf('%020d%020d', 1000 - (klassen_ranking.index(a) || 1000), klassen_stats[a] * 1000)
                vb = sprintf('%020d%020d', 1000 - (klassen_ranking.index(b) || 1000), klassen_stats[b] * 1000)
                vb <=> va
            end.each.with_index do |klasse, index|
                place = "#{index + 1}."
                percent = klassen_stats[klasse]
                bgcol = get_gradient(['#cc0000', '#f4951b', '#ffe617', '#80bc42'], percent / 100.0)
                c = ''
                star_span = ''
                if stats[klasse][:count][LOGIN_STATS_D.last] == stats[klasse][:total]
                    c = 'complete'
                    star_span = "<i class='fa fa-star'></i>"
                else
                    place = ''
                end
                io.puts "<span class='ranking #{c}' style='background-color: #{bgcol};'>#{star_span}<span class='klasse'>#{tr_klasse(klasse)}</span><span class='percent'>#{percent.to_i}%</span>"
                io.puts "<span class='place'>#{place}</span>" unless place.empty?
                io.puts "</span>"
            end
            io.string
        end
    end
end
