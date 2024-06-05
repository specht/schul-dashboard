PROJEKT_VOTE_CODEPOINTS = [0x1fae5, 0x1f914, 0x1f60d, 0x1f525]
PROJEKT_VOTE_LABELS = [
    'Ich habe kein Interesse an diesem Projekt.',
    'Ich könnte mir vorstellen, an diesem Projekt teilzunehmen.',
    'Ich würde mich freuen, an diesem Projekt teilzunehmen.',
    'Ich würde wirklich sehr gern an diesem Projekt teilnehmen.',
]

class Main < Sinatra::Base

    def user_eligible_for_projekt_katalog?
        return true if teacher_logged_in?
        return schueler_logged_in?
    end

    def user_eligible_for_projektwahl?
        return false unless schueler_logged_in?
        return false unless projekttage_phase() == 3
        klassenstufe = @session_user[:klassenstufe] || 7
        return klassenstufe >= 5 && klassenstufe <= 9
    end

    def parse_projekt_node(p)
        {
            :nr => p[:nr],
            :title => p[:title],
            :description => p[:description],
            :photo => p[:photo],
            :exkursion_hint => p[:exkursion_hint],
            :extra_hint => p[:extra_hint],
            :categories => p[:categories],
            :min_klasse => p[:min_klasse],
            :max_klasse => p[:max_klasse],
            :capacity => p[:capacity],
            :organized_by => [],
            :supervised_by => [],
        }
    end

    def get_projekte
        projekte = {}
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekt)-[:ORGANIZED_BY]->(u:User)
            RETURN p, u.email;
        END_OF_QUERY
            p = row['p']
            projekte[p[:nr]] ||= parse_projekt_node(p)
            projekte[p[:nr]][:organized_by] << row['u.email']
        end

        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekt)-[:SUPERVISED_BY]->(u:User)
            RETURN p, u.email;
        END_OF_QUERY
            p = row['p']
            projekte[p[:nr]] ||= parse_projekt_node(p)
            projekte[p[:nr]][:supervised_by] << row['u.email']
        end
        projekte_list = []
        projekte.each_pair do |nr, p|
            p[:organized_by] = p[:organized_by].sort.uniq
            p[:supervised_by] = p[:supervised_by].sort.uniq
            p[:klassen_label] = '–'
            if p[:min_klasse] && p[:max_klasse]
                if p[:min_klasse] == p[:max_klasse]
                    p[:klassen_label] = "nur #{p[:min_klasse]}."
                else
                    p[:klassen_label] = "#{p[:min_klasse]}. – #{p[:max_klasse]}."
                end
            end
            projekte_list << p
        end

        projekte_list.sort! do |a, b|
            (a[:nr].to_i == b[:nr].to_i) ?
            (a[:nr] <=> b[:nr]) :
            (a[:nr].to_i <=> b[:nr].to_i)
        end

        projekte_list
    end

    post '/api/get_projekte' do
        require_user!
        result = {:projekte => get_projekte()}
        if user_eligible_for_projektwahl?
            vote_for_project_nr = {}
            latest_ts = 0
            neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]}).each do |row|
                MATCH (u:User {email: $email})-[v:VOTED_FOR]->(p:Projekt)
                RETURN p.nr, v.vote, v.ts_updated;
            END_OF_QUERY
                vote_for_project_nr[row['p.nr']] = row['v.vote']
                latest_ts = row['v.ts_updated'] if row['v.ts_updated'] > latest_ts
            end
            result[:latest_ts] = latest_ts
            result[:projekte].map! do |p|
                p[:session_user_vote] = vote_for_project_nr[p[:nr]] || 0
                p
            end
            begin
                result[:ts] = JSON.parse(File.read('/internal/projekttage/votes/ts.json'))
                result[:my_vote_data] = JSON.parse(File.read("/internal/projekttage/votes/#{@session_user[:email]}.json"))
                result[:project_data] = JSON.parse(File.read("/internal/projekttage/votes/projects.json"))
            rescue
            end
        end
        respond(result)
    end

    post '/api/get_project_data' do
        require_user!
        result = {}
        begin
            result[:ts] = JSON.parse(File.read('/internal/projekttage/votes/ts.json'))
            result[:project_data] = JSON.parse(File.read("/internal/projekttage/votes/projects.json"))
            result[:my_vote_data] = JSON.parse(File.read("/internal/projekttage/votes/#{@session_user[:email]}.json"))
        rescue
        end
        respond(result)
    end

    post '/api/get_projekte_for_orga_sus' do
        require_user!
        projekte = get_projekte()
        projekte.select! do |p|
            p[:organized_by].include?(@session_user[:email])
        end
        respond(:projekte => projekte)
    end

    post '/api/update_project' do
        require_user!
        data = parse_request_data(:required_keys => [:nr, :title, :description, :exkursion_hint, :extra_hint], :max_body_length => 16384, :max_string_length => 8192)
        projekt = neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :title => data[:title], :description => data[:description], :exkursion_hint => data[:exkursion_hint], :extra_hint => data[:extra_hint], :ts => Time.now.to_i})['p']
            MATCH (p:Projekt {nr: $nr})-[:ORGANIZED_BY]->(u:User {email: $email})
            SET p.title = $title
            SET p.description = $description
            SET p.exkursion_hint = $exkursion_hint
            SET p.extra_hint = $extra_hint
            SET p.ts_updated = $ts
            RETURN p;
        END_OF_QUERY
    end

    post '/api/set_photo_for_project' do
        require_user!
        data = parse_request_data(:required_keys => [:nr, :photo])
        projekt = neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :photo => data[:photo], :ts => Time.now.to_i})
            MATCH (p:Projekt {nr: $nr})-[:ORGANIZED_BY]->(u:User {email: $email})
            SET p.photo = $photo
            SET p.ts_updates = $ts
            RETURN p;
        END_OF_QUERY
    end

    post '/api/delete_photo_for_project' do
        require_user!
        data = parse_request_data(:required_keys => [:nr])
        projekt = neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :ts => Time.now.to_i})
            MATCH (p:Projekt {nr: $nr})-[:ORGANIZED_BY]->(u:User {email: $email})
            REMOVE p.photo
            SET p.ts_updated = $ts
            RETURN p;
        END_OF_QUERY
    end

    post '/api/vote_for_project' do
        require_user!
        assert(user_eligible_for_projektwahl?)
        data = parse_request_data(:required_keys => [:nr, :vote], :types => {:vote => Integer})
        ts = Time.now.to_i
        if data[:vote] == 0
            neo4j_query(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email]})
                MATCH (u:User {email: $email})-[v:VOTED_FOR]->(p:Projekt {nr: $nr})
                DELETE v;
            END_OF_QUERY
        else
            neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :ts => ts, :vote => data[:vote]})
                MATCH (u:User {email: $email})
                MATCH (p:Projekt {nr: $nr})
                MERGE (u)-[v:VOTED_FOR]->(p)
                SET v.ts_updated = $ts
                SET v.vote = $vote
                RETURN p;
            END_OF_QUERY
        end
        trigger_update_images()
        respond(:ts => ts)
    end

    def print_projekt_interesse
        projekt = nil
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]}).each do |row|
            MATCH (p:Projekt)-[:ORGANIZED_BY]->(u:User {email: $email})
            RETURN p;
        END_OF_QUERY
            projekt = row['p']
        end
        return '' if projekt.nil? || projekt[:min_klasse].nil? || projekt[:max_klasse].nil? || projekt[:capacity].nil?

        votes = {}
        neo4j_query(<<~END_OF_QUERY, {:nr => projekt[:nr]}).each do |row|
            MATCH (u:User)-[r:VOTED_FOR]->(p:Projekt {nr: $nr})
            RETURN u.email, r;
        END_OF_QUERY
            email = row['u.email']
            next unless @@user_info[email]
            next unless @@user_info[email][:roles].include?(:schueler)
            klassenstufe = @@user_info[email][:klassenstufe] || 7
            vote = row['r'][:vote]
            key = "#{klassenstufe}/#{vote}"
            votes[key] ||= 0
            votes[key] += 1
            key = "klassenstufe/#{klassenstufe}"
            votes[key] ||= 0
            votes[key] += 1
            key = "vote/#{vote}"
            votes[key] ||= 0
            votes[key] += 1
            key = "total"
            votes[key] ||= 0
            votes[key] += 1
        end

        StringIO.open do |io|
            io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-sm' style='width: unset;'>"
            io.puts "<tr>"
            io.puts "<th>Klassenstufe</th>"
            (projekt[:min_klasse]..projekt[:max_klasse]).each do |klasse|
                io.puts "<th class='#{klasse == projekt[:min_klasse] ? 'cbl' : ''}' style='text-align: center;'>#{klasse}.</th>"
            end
            io.puts "<th class='cbl' style='text-align: center;'>Σ</th>"
            io.puts "</tr>"
            ndash = "<span class='text-muted'>&ndash;</span>"
            [3, 2, 1].each do |vote|
                io.puts "<tr>"
                io.puts "<td>#{PROJEKT_VOTE_CODEPOINTS[vote].chr(Encoding::UTF_8)} #{PROJEKT_VOTE_LABELS[vote]}</td>"
                (projekt[:min_klasse]..projekt[:max_klasse]).each do |klasse|
                    count = votes["#{klasse}/#{vote}"] || ndash
                    io.puts "<td class='#{klasse == projekt[:min_klasse] ? 'cbl' : ''}' style='text-align: center;'>#{count}</td>"
                end
                count = votes["vote/#{vote}"] || ndash
                io.puts "<td class='cbl' style='text-align: center;'>#{count}</td>"
                io.puts "</tr>"
            end
            io.puts "<tr>"
            io.puts "<td>Σ</td>"
            (projekt[:min_klasse]..projekt[:max_klasse]).each do |klasse|
                count = votes["klassenstufe/#{klasse}"] || ndash
                io.puts "<td class='#{klasse == projekt[:min_klasse] ? 'cbl' : ''}' style='text-align: center;'>#{count}</td>"
            end
            count = votes["total"] || ndash
            io.puts "<td class='cbl' style='text-align: center;'>#{count}</td>"
            io.puts "</tr>"
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
    end

    def print_projekt_interesse_stats
        projekt = nil
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]}).each do |row|
            MATCH (p:Projekt)-[:ORGANIZED_BY]->(u:User {email: $email})
            RETURN p;
        END_OF_QUERY
            projekt = row['p']
        end
        return '' if projekt.nil? || projekt[:min_klasse].nil? || projekt[:max_klasse].nil? || projekt[:capacity].nil?

        data = nil
        begin
            data = JSON.parse(File.read("/internal/projekttage/votes/project-#{projekt[:nr]}.json"))
        rescue
        end
        ts_data = nil
        begin
            ts_data = JSON.parse(File.read("/internal/projekttage/votes/ts.json"))
        rescue
        end
        return '' if ts_data.nil?

        StringIO.open do |io|
            io.puts "<h4>Vorschau deiner Projektgruppe</h4>"
            io.puts "<p>Aktuell würde deine Projektgruppe ungefähr wie folgt aussehen:</p>"
            io.puts "<ul style='list-style: disc; margin-left: 1.5em;'>"
            io.puts "<li>#{data['geschlecht_m'] + data['geschlecht_w']} Teilnehmer:innen, davon #{data['geschlecht_m']} Jungen und #{data['geschlecht_w']} Mädchen</li>"
            io.puts "<li>Klassenstufen:<ul style='list-style: disc; margin-left: 1.5em;'>"
            x = ((projekt[:min_klasse] || 5)..(projekt[:max_klasse] || 9)).select do |klasse|
                (data['klasse'][klasse.to_s] || 0) > 0
            end.map do |klasse|
                "<li>#{data['klasse'][klasse.to_s]} Kind#{data['klasse'][klasse.to_s] > 1 ? 'er' : ''} aus der #{klasse}. Klasse</li>"
            end
            io.puts x.join('')
            io.puts "</ul></li>"
            io.puts "<li>Motivation:<ul style='list-style: disc; margin-left: 1.5em;'>"
            x = [3, 2, 1, 0].select do |vote|
                (data['vote'][vote.to_s] || 0) > 0
            end.map do |vote|
                "<li>#{data['vote'][vote.to_s]} Kind#{data['vote'][vote.to_s] > 1 ? 'er' : ''} mit der Wahl: #{PROJEKT_VOTE_CODEPOINTS[vote].chr(Encoding::UTF_8)} »#{PROJEKT_VOTE_LABELS[vote]}«</li>"
            end
            io.puts x.join('')
            io.puts "</ul></li>"
            io.puts "</ul>"
            if data['vote']['0'] * 100 / (data['geschlecht_m'] + data['geschlecht_w']) > 10
                io.puts "<p>Hinweis: Du kannst die Motivation deiner Teilnehmer:innen erhöhen, indem du ggfs. deinen Titel, deinen Werbetext und / oder dein Projektbild aktualisierst.</p>"
            end
            io.puts "<p>Bitte beachte, dass sich die Zusammensetzung deiner Gruppe noch ändern wird, abhängig vom weiteren Wahlverhalten, Umwahlen oder Anpassungen in eurem Projekt.</p>"
            io.puts "<p>Bisher haben #{ts_data['email_count_voted']} von #{ts_data['email_count_total']} Schülerinnen und Schülern ihre Projekte gewählt:"
            io.puts "<div class='progress'>"
            p = ts_data['email_count_voted'] * 100 / ts_data['email_count_total']
            io.puts "<div class='bg-success progress-bar progress-bar-striped progress-bar-animated' role='progressbar' style='width: #{p}%;'>#{p.round}%</div>"
            io.puts "</div>"
            io.puts "</p>"
            io.string
        end
    end

    def score_for_project(nr, project_data)
        vote = project_data['vote'] || {}
        x = [vote['0'] || 0, vote['1'] || 0, vote['2'] || 0, vote['3'] || 0]
        return -(x[0] * 3 + x[1] - x[2] - 3 * x[3]).to_f / (x.sum + 1)
    end

    def print_projekttage_vote_summary
        return '' unless teacher_logged_in?
        StringIO.open do |io|
            votes = {}
            votes_for_projekt = {}
            emails = Set.new()
            neo4j_query(<<~END_OF_QUERY).each do |row|
                MATCH (u:User)-[r:VOTED_FOR]->(p:Projekt)
                RETURN u.email, r, p.nr;
            END_OF_QUERY
                email = row['u.email']
                emails << email
                next unless @@user_info[email]
                next unless @@user_info[email][:roles].include?(:schueler)
                klassenstufe = @@user_info[email][:klassenstufe] || 7
                klassenstufe = 'WK' if @@user_info[email][:klasse][0, 2] == 'WK'
                vote = row['r'][:vote]
                key = "#{klassenstufe}/#{vote}"
                votes[key] ||= 0
                votes[key] += 1
                key = "#{row['p.nr']}/#{klassenstufe}"
                votes_for_projekt[key] ||= 0
                votes_for_projekt[key] += 1
                key = "#{row['p.nr']}/#{vote}"
                votes_for_projekt[key] ||= 0
                votes_for_projekt[key] += 1
                key = "#{row['p.nr']}"
                votes_for_projekt[key] ||= 0
                votes_for_projekt[key] += 1
                key = "votes_by_email/#{email}"
                votes_for_projekt[key] ||= 0
                votes_for_projekt[key] += 1
            end

            KLASSEN_ORDER.each do |klasse|
                @@schueler_for_klasse[klasse].each do |email|
                    key = "votes_by_email/#{email}"
                    count = votes_for_projekt[key] || 0
                    count = 10 if count > 10
                    key = "votes_by_klasse/#{@@user_info[email][:klasse]}/#{count}"
                    votes_for_projekt[key] ||= 0
                    votes_for_projekt[key] += 1
                end
            end

            io.puts "<h4>Projizierte Zusammensetzung der Projektgruppen</h4>"
            io.puts "<p>Aus dieser Tabelle lässt sich ganz gut ablesen, welche Projekte gut ankommen und welche eher weniger.</p>"
            io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-sm' style='width: unset;'>"
            io.puts "<tr>"
            io.puts "<th>Projekt</th>"
            [5, 6, 7, 8, 9, 3, 2, 1, 0, 'm', 'w', 'Σ'].each do |klasse|
                if [0, 1, 2, 3].include?(klasse)
                    io.puts "<th class='#{[5, 3, 'Σ'].include?(klasse) ? 'cbl' : ''}' style='text-align: center;'>#{PROJEKT_VOTE_CODEPOINTS[klasse].chr(Encoding::UTF_8)}</th>"
                else
                    io.puts "<th class='#{[5, 3, 'm', 'Σ'].include?(klasse) ? 'cbl' : ''}' style='text-align: center;'>#{klasse}#{['WK', 'Σ'].include?(klasse) ? '' : '.'}</th>"
                end
            end
            io.puts "</tr>"
            ndash = "<span class='text-muted'>&ndash;</span>"
            all_project_data = {}
            get_projekte.each do |p|
                all_project_data[p[:nr]] = {}
                begin
                    all_project_data[p[:nr]] = JSON.parse(File.read("/internal/projekttage/votes/project-#{p[:nr]}.json"))
                rescue
                end
            end
            get_projekte.sort do |a, b|
                score_for_project(b, all_project_data[b[:nr]]) <=> score_for_project(a, all_project_data[a[:nr]])
            end.each do |projekt|
                next if projekt[:capacity] == 0
                project_data = all_project_data[projekt[:nr]]
                io.puts "<tr>"
                io.puts "<td>#{projekt[:title]}</td>"
                [5, 6, 7, 8, 9].each do |klasse|
                    io.puts "<td class='#{[5, 3, 'Σ'].include?(klasse) ? 'cbl' : ''}' style='text-align: center;'>#{(project_data['klasse'] || {})[klasse.to_s] || ndash }</td>"
                end
                [3, 2, 1, 0].each do |vote|
                    io.puts "<td class='#{[5, 3, 'Σ'].include?(vote) ? 'cbl' : ''}' style='text-align: center;'>#{(project_data['vote'] || {})[vote.to_s] || ndash }</td>"
                end
                io.puts "<td class='cbl' style='text-align: center;'>#{project_data['geschlecht_m'] || ndash}</td>"
                io.puts "<td style='text-align: center;'>#{project_data['geschlecht_w'] || ndash}</td>"
                io.puts "<td class='cbl' style='text-align: center;'>#{(project_data['geschlecht_m'] || 0) + (project_data['geschlecht_w'] || 0)}</td>"
                io.puts "</tr>"
            end
            io.puts "</table>"
            io.puts "</div>"

            io.puts "<h4>Projektinteresse</h4>"
            io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-sm' style='width: unset;'>"
            io.puts "<tr>"
            io.puts "<th>Projekt</th>"
            [5, 6, 7, 8, 9, 'WK', 3, 2, 1, 'Σ'].each do |klasse|
                if [1, 2, 3].include?(klasse)
                    io.puts "<th class='#{[5, 3, 'Σ'].include?(klasse) ? 'cbl' : ''}' style='text-align: center;'>#{PROJEKT_VOTE_CODEPOINTS[klasse].chr(Encoding::UTF_8)}</th>"
                else
                    io.puts "<th class='#{[5, 3, 'Σ'].include?(klasse) ? 'cbl' : ''}' style='text-align: center;'>#{klasse}#{['WK', 'Σ'].include?(klasse) ? '' : '.'}</th>"
                end
            end
            io.puts "</tr>"
            ndash = "<span class='text-muted'>&ndash;</span>"
            get_projekte.sort do |a, b|
                (votes_for_projekt["#{b[:nr]}"] || 0) <=> (votes_for_projekt["#{a[:nr]}"] || 0)
            end.each do |projekt|
                next if projekt[:capacity] == 0
                io.puts "<tr>"
                io.puts "<td>#{projekt[:title]}</td>"
                [5, 6, 7, 8, 9, 'WK'].each do |klasse|
                    io.puts "<td class='#{[5, 3, 'Σ'].include?(klasse) ? 'cbl' : ''}' style='text-align: center;'>#{votes_for_projekt["#{projekt[:nr]}/#{klasse}"] || ndash }</td>"
                end
                [3, 2, 1].each do |vote|
                    io.puts "<td class='#{[5, 3, 'Σ'].include?(vote) ? 'cbl' : ''}' style='text-align: center;'>#{votes_for_projekt["#{projekt[:nr]}/#{vote}"] || ndash }</td>"
                end
                io.puts "<td class='cbl' style='text-align: center;'>#{votes_for_projekt["#{projekt[:nr]}"] || ndash }</td>"
                io.puts "</tr>"
            end
            io.puts "</table>"
            io.puts "</div>"

            io.puts "<h4>Interesse pro Klassenstufe</h4>"
            io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-sm' style='width: unset;'>"
            io.puts "<tr>"
            io.puts "<th>Klassenstufe</th>"
            [5, 6, 7, 8, 9, 'WK', 'Σ'].each do |klasse|
                io.puts "<th style='text-align: center;' class='#{[5, 'Σ'].include?(klasse) ? 'cbl' : ''}'>#{['WK', 'Σ'].include?(klasse) ? '' : 'Klassenstufe'} #{klasse}</th>"
            end
            io.puts "</tr>"
            [3, 2, 1].each do |vote|
                io.puts "<tr>"
                io.puts "<td>#{PROJEKT_VOTE_CODEPOINTS[vote].chr(Encoding::UTF_8)} #{PROJEKT_VOTE_LABELS[vote]}</td>"
                sum = 0
                [5, 6, 7, 8, 9, 'WK', 'Σ'].each do |klasse|
                    count = votes["#{klasse}/#{vote}"] || ndash
                    sum += votes["#{klasse}/#{vote}"] || 0
                    count = sum if klasse == 'Σ'
                    io.puts "<td class='#{[5, 'Σ'].include?(klasse) ? 'cbl' : ''}' style='text-align: center;'>#{count}</td>"
                end
                io.puts "</tr>"
            end
            io.puts "</table>"
            io.puts "</div>"

            io.puts "<h4>Anzahl der gewählten Projekte pro Klasse</h4>"
            io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-sm' style='width: unset;'>"
            io.puts "<tr>"
            io.puts "<th>Ausgewählte Projekte</th>"
            io.puts "<th>keins</th>"
            (1..10).each do |count|
                io.puts "<th style='text-align: center;'>#{count}#{count == 10 ? '+' : ''}</th>"
            end
            io.puts "</tr>"
            KLASSEN_ORDER.each do |klasse|
                next unless klasse.to_i <= 9 || klasse[0, 2] == 'WK'
                io.puts "<tr>"
                io.puts "<td>Klasse #{tr_klasse(klasse)}</td>"
                (0..10).each do |count|
                    key = "votes_by_klasse/#{klasse}/#{count}"
                    count = votes_for_projekt[key] || ndash
                    io.puts "<td class='cbl' style='text-align: center;'>#{count}</td>"
                end
                io.puts "</tr>"
            end
            io.puts "</table>"
            io.puts "</div>"

            io.string
        end

    end
end
