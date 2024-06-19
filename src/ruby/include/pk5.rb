PK5_KEYS = [
    :themengebiet,
    :referenzfach,
    :betreuende_lehrkraft,
    :fas,
    :betreuende_lehrkraft_fas,
    :fragestellung
]

PK5_KEY_LABELS = {
    :themengebiet => 'Themengebiet',
    :referenzfach => 'Referenzfach',
    :betreuende_lehrkraft => 'Betreuende Lehrkraft im Referenzfach',
    :fas => 'fächerübergreifender Aspekt',
    :betreuende_lehrkraft_fas => 'Betreuende Lehrkraft im fächerübergreifenden Aspekt',
    :fragestellung => 'Fragestellung',
}

class Main < Sinatra::Base

    def get_my_pk5(email)
        require_user!
        result = nil
        neo4j_query(<<~END_OF_QUERY, {:email => email}).each do |row|
            MATCH (p:Pk5)-[:BELONGS_TO]->(u:User {email: $email})
            WITH p
            MATCH (p)-[:BELONGS_TO]->(ou:User)
            RETURN p, ou.email;
        END_OF_QUERY
            if result.nil?
                result = row['p']
                result[:sus] = []
            end
            result[:sus] << row['ou.email']
        end
        if result.nil?
            {
                :sus => [@@user_info[email][:display_name]],
            }
        else
            if result[:sus]
                result[:sus].sort! do |a, b|
                    @@user_info[a][:last_name].downcase <=> @@user_info[b][:last_name].downcase
                end
                result[:sus].map! { |email| @@user_info[email][:display_name_official] }
            end
            if result[:betreuende_lehrkraft]
                result[:betreuende_lehrkraft] = @@user_info[result[:betreuende_lehrkraft]][:display_name_official]
            end
            result
        end
    end

    def my_pk5_history(email)
        StringIO.open do |io|
            entries = neo4j_query(<<~END_OF_QUERY, {:email => email}).to_a
                MATCH (eu:User)<-[:BY]-(pc:Pk5Change)-[:TO]->(p:Pk5)-[:BELONGS_TO]->(u:User {email: $email})
                RETURN pc, eu.email
                ORDER BY pc.ts;
            END_OF_QUERY
            if entries.empty?
                io.puts "<em>(keine Einträge)</em>"
            else
                current_date = nil
                entries.each do |entry|
                    pc = entry['pc']
                    ts = pc[:ts]
                    ts_d = Time.at(ts)
                    entry_date = "#{WEEKDAYS_LONG[ts_d.wday]}, den #{ts_d.strftime("%d.%m.%Y")}"
                    if entry_date != current_date
                        io.puts "<div class='history_date'>#{entry_date}</div>"
                        if current_date.nil?
                            io.puts "<div class='history_entry'>Vorgang erstellt durch #{@@user_info[entry['eu.email']][:display_name_official]}</div>"
                        end
                        current_date = entry_date
                    end
                    if pc[:type] == 'update_value'
                        key = pc[:key].to_sym
                        value = pc[:value]
                        if key == :betreuende_lehrkraft
                            value = (@@user_info[value] || {})[:display_name_official] || value
                        end
                        if value.nil?
                            io.puts "<div class='history_entry'>#{PK5_KEY_LABELS[key]} gelöscht durch #{@@user_info[entry['eu.email']][:display_name_official]}</div>"
                        else
                            io.puts "<div class='history_entry'>#{PK5_KEY_LABELS[key]} geändert auf <strong>»#{value}«</strong> durch #{@@user_info[entry['eu.email']][:display_name_official]}</div>"
                        end
                    end
                end
            end
            io.string
        end
    end

    post '/api/my_pk5_history' do
        require_user!
        data = parse_request_data(
            :optional_keys => [
                :sus_email,
            ],
            :max_body_length => 16384,
            :max_string_length => 8192
        )
        sus_email = @session_user[:email]
        if user_with_role_logged_in?(:oko)
            sus_email = data[:sus_email] if data[:sus_email]
        end
        respond(:html => my_pk5_history(sus_email))
    end

    post '/api/update_pk5' do
        require_user!
        data = parse_request_data(
            :optional_keys => [
                :sus_email,
                :themengebiet,
                :referenzfach,
                :betreuende_lehrkraft,
            ],
            :max_body_length => 16384,
            :max_string_length => 8192
        )
        sus_email = @session_user[:email]
        if user_with_role_logged_in?(:oko)
            sus_email = data[:sus_email] if data[:sus_email]
        end
        ts = Time.now.to_i
        transaction do
            p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
                MATCH (u:User {email: $sus_email})
                MERGE (p:Pk5)-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            [:themengebiet, :referenzfach, :betreuende_lehrkraft].each do |key|
                if data.include?(key)
                    value = data[key]
                    if key == :referenzfach
                        all_faecher = File.read('/data/pk5/faecher.txt').split("\n").map { |x| x.strip }.reject { |x| x.empty? }
                        value = nil unless all_faecher.include?(value)
                    end
                    if key == :betreuende_lehrkraft
                        value = @@users_for_role[:teacher].select do |email|
                            @@user_info[email][:display_name_official] == value
                        end.first
                    end
                    debug "#{key} => #{value}"
                    if (value || '') != (p[key] || '')
                        neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, key => value})
                            MATCH (p:Pk5)-[:BELONGS_TO]->(u:User {email: $sus_email})
                            SET p.#{key.to_s} = $#{key.to_s}
                            RETURN p;
                        END_OF_QUERY
                        neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :key => key, :value => value, :ts => ts, :editor_email => @session_user[:email]})
                            MATCH (eu:User {email: $editor_email})
                            MATCH (p:Pk5)-[:BELONGS_TO]->(:User {email: $sus_email})
                            CREATE (eu)<-[:BY]-(c:Pk5Change)-[:TO]->(p)
                            SET c.type = 'update_value'
                            SET c.key = $key
                            SET c.value = $value
                            SET c.ts = $ts
                            RETURN p;
                        END_OF_QUERY
                    end
                end
            end
        end
        respond(:yay => 'sure', :result => get_my_pk5(sus_email))
    end

    def print_pk5_overview
        require_teacher!
        StringIO.open do |io|
            io.puts "<div style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-condensed table-striped narrow' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Prüfungskandidat:innen</th>"
            io.puts "<th>Themengebiet</th>"
            io.puts "<th>Referenzfach</th>"
            io.puts "<th>Lehrkraft</th>"
            io.puts "<th>fächerübergreifender Aspekt</th>"
            io.puts "<th>Lehrkraft</th>"
            # io.puts "<th>Fragestellung</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            seen_sus = Set.new()
            pk5_hash = {}
            pk5_by_email = {}
            neo4j_query(<<~END_OF_QUERY).each do |row|
                MATCH (p:Pk5)-[:BELONGS_TO]->(u:User)
                RETURN ID(p) AS id, p, u.email;
            END_OF_QUERY
                id = row['id']
                unless pk5_hash.include?(id)
                    pk5_hash[id] = row['p']
                    pk5_hash[id][:sus] = []
                end
                pk5_hash[id][:sus] << row['u.email']
                pk5_by_email[row['u.email']] = id
            end

            @@schueler_for_klasse[PK5_CURRENT_KLASSE].each do |email|
                next if seen_sus.include?(email)
                seen_sus << email
                pk5 = nil
                if pk5_by_email[email]
                    pk5 = pk5_hash[pk5_by_email[email]]
                end
                if pk5
                    pk5[:sus].each do |x|
                        seen_sus << x
                    end
                end
                if pk5
                    io.puts "<tr data-email='#{email}'>"
                    io.puts "<td>#{pk5[:sus].map { |x| @@user_info[x][:display_name]}.join(', ')}</td>"
                    io.puts "<td>#{CGI.escapeHTML(pk5[:themengebiet] || '–')}</td>"
                    io.puts "<td>#{CGI.escapeHTML(pk5[:referenzfach] || '–')}</td>"
                    io.puts "<td>#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft]] || {})[:display_name_official]) || '–')}</td>"
                    io.puts "<td>#{CGI.escapeHTML(pk5[:fas] || '–')}</td>"
                    io.puts "<td>#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft_fas]] || {})[:display_name_official]) || '–')}</td>"
                    # io.puts "<td>#{CGI.escapeHTML(pk5[:fragestellung] || '–')}</td>"
                    io.puts "</tr>"
                else
                    io.puts "<tr data-email='#{email}'>"
                    io.puts "<td>#{@@user_info[email][:display_name]}</td>"
                    io.puts "<td>–</td>"
                    io.puts "<td>–</td>"
                    io.puts "<td>–</td>"
                    io.puts "<td>–</td>"
                    io.puts "<td>–</td>"
                    # io.puts "<td>–</td>"
                    io.puts "</tr>"
                end
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
    end
end
