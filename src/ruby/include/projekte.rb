PROJEKTTAGE_KEYS = [
    :nr,
    :name,
    :ziel,
    :teilnehmer_min,
    :teilnehmer_max,
    :klassenstufe_min,
    :klassenstufe_max,
    :grobplanung1,
    :grobplanung2,
    :grobplanung3,
    :produkt,
    :praesentationsidee,
    :material,
    :kosten_finanzierungsidee,
    :lehrkraft_wunsch,
    :raumwunsch,
    :planung_exkursion,
    :planung_tablets,
    :werbetext,
    :raum,
    :lehrkraft
]

PROJEKTTAGE_KEY_LABELS = {
    :nr => 'Nr.',
    :name => 'Name des Projekts',
    :ziel => 'Ziel',
    :teilnehmer_min => 'Gewünschte Teilnehmerzahl (min.)',
    :teilnehmer_max => 'Gewünschte Teilnehmerzahl (max.)',
    :klassenstufe_min => 'Klassenstufe (min.)',
    :klassenstufe_max => 'Klassenstufe (max.)',
    :grobplanung1 => 'Grobplanung 1. Tag (Donnerstag)',
    :grobplanung2 => 'Grobplanung 2. Tag (Freitag)',
    :grobplanung3 => 'Grobplanung 3. Tag (Montag)',
    :produkt => 'Produkt, das erarbeitet wird',
    :praesentationsidee => 'Präsentationsidee für das Schulfest',
    :material => 'Benötigtes Material',
    :kosten_finanzierungsidee => 'Entstehende Kosten und Finanzierungsidee',
    :lehrkraft_wunsch => 'Wunsch für betreuende Lehrkraft',
    :raumwunsch => 'Raumwunsch',
    :planung_exkursion => 'Planung Exkursion',
    :planung_tablets => 'Benötigte Tablets',
    :werbetext => 'Werbetext für den Projektkatalog',
    :raum => 'Raum',
    :lehrkraft => 'Betreuende Lehrkraft',
}

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

    def user_was_eligible_for_projektwahl?
        return false unless schueler_logged_in?
        return false unless projekttage_phase() >= 4
        klassenstufe = @session_user[:klassenstufe] || 7
        return klassenstufe >= 5 && klassenstufe <= 9
    end

    def parse_projekt_node(p)
        {
            :nr => p[:nr],
            :name => p[:name],
            :werbetext => p[:werbetext],
            :photo => p[:photo],
            :categories => p[:categories],
            :klassenstufe_min => p[:klassenstufe_min],
            :klassenstufe_max => p[:klassenstufe_max],
            :teilnehmer_max => p[:teilnehmer_max],
            :organized_by => [],
            :supervised_by => [],
        }
    end

    def get_projekte
        projekte = {}
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User)
            RETURN p, u.email;
        END_OF_QUERY
            p = row['p']
            next if (p[:nr] || '').strip.empty?
            projekte[p[:nr]] ||= parse_projekt_node(p)
            projekte[p[:nr]][:organized_by] << row['u.email']
        end

        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekttage)-[:SUPERVISED_BY]->(u:User)
            RETURN p, u.email;
        END_OF_QUERY
            p = row['p']
            next if (p[:nr] || '').strip.empty?
            projekte[p[:nr]] ||= parse_projekt_node(p)
            projekte[p[:nr]][:supervised_by] << row['u.email']
        end
        projekte_list = []
        projekte.each_pair do |nr, p|
            p[:organized_by] = p[:organized_by].sort.uniq
            p[:supervised_by] = p[:supervised_by].sort.uniq
            p[:klassen_label] = '–'
            if p[:klassenstufe_min] && p[:klassenstufe_max]
                if p[:klassenstufe_min] == p[:klassenstufe_max]
                    p[:klassen_label] = "nur #{p[:klassenstufe_min]}."
                else
                    p[:klassen_label] = "#{p[:klassenstufe_min]}. – #{p[:klassenstufe_max]}."
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
        if user_eligible_for_projektwahl? || user_was_eligible_for_projektwahl?
            vote_for_project_nr = {}
            latest_ts = 0
            neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]}).each do |row|
                MATCH (u:User {email: $email})-[v:VOTED_FOR]->(p:Projekttage)
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
                path = "/internal/projekttage/votes/assign-result.json"
                if File.exist?(path)
                    temp = JSON.parse(File.read(path))
                    result[:assigned_projekt_error] = temp['error_for_email'][@session_user[:email]] || 0
                end
            rescue
            end
        end
        if user_was_eligible_for_projektwahl?
            # path = '/internal/projekttage/votes/verdicts.json'
            # if File.exist?(path)
                # verdict_for_email = JSON.parse(File.read(path))
                # result[:verdict] = verdict_for_email[@session_user[:email]]
                begin
                    result[:assigned_projekt] = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})['p.nr']
                        MATCH (u:User {email: $email})-[:ASSIGNED_TO]->(p:Projekttage)
                        RETURN p.nr;
                    END_OF_QUERY
                rescue
                end
            # end
        end
        respond(result)
    end    

    def get_my_projekttage(email)
        require_user!
        result = nil
        neo4j_query(<<~END_OF_QUERY, {:email => email}).each do |row|
            MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $email})
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
            result[:teilnehmer_min] ||= 1
            result[:teilnehmer_min] ||= 20
            result[:klassenstufe_min] ||= 5
            result[:klassenstufe_max] ||= 9
            if result[:sus]
                result[:sus].sort! do |a, b|
                    @@user_info[a][:last_name].downcase <=> @@user_info[b][:last_name].downcase
                end
                result[:sus].map! { |teacher_email| @@user_info[teacher_email][:display_name_official] }
            end
            result
        end
    end

    def my_projekttage_history(email)
        StringIO.open do |io|
            entries = neo4j_query(<<~END_OF_QUERY, {:email => email}).to_a
                MATCH (eu:User)<-[:BY]-(pc:ProjekttageChange)-[:TO]->(p:Projekttage)-[:BELONGS_TO]->(u:User {email: $email})
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
                            io.puts "<div class='history_entry'>Vorgang erstellt durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                        end
                        current_date = entry_date
                    end
                    if pc[:type] == 'update_value'
                        key = pc[:key].to_sym
                        value = pc[:value]
                        if value.nil?
                            io.puts "<div class='history_entry'>#{PROJEKTTAGE_KEY_LABELS[key]} gelöscht durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                        else
                            io.puts "<div class='history_entry'>#{PROJEKTTAGE_KEY_LABELS[key]} geändert auf <strong>»#{value}«</strong> durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                        end
                    elsif pc[:type] == 'invite_sus'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:other_email]][:display_name]}</strong> zum Projekt eingeladen durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                    elsif pc[:type] == 'uninvite_sus'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:other_email]][:display_name]}</strong> vom Projekt ausgeladen durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                    elsif pc[:type] == 'accept_invitation'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:email]][:display_name]}</strong> hat die Einladung zum Projekt angenommen</div>"
                    elsif pc[:type] == 'reject_invitation'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:email]][:display_name]}</strong> hat die Einladung zum Projekt abgelehnt</div>"
                    elsif pc[:type] == 'comment'
                        io.puts "<div class='history_entry'>kommentiert von #{@@user_info[entry['eu.email']][:display_name_official_dativ]}: <b>#{pc[:comment].gsub("\n", '<br>')}</b></div>"
                    elsif pc[:type] == 'upload_photo'
                        io.puts "<div class='history_entry'>Bild hochgeladen von #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                    elsif pc[:type] == 'delete_photo'
                        io.puts "<div class='history_entry'>Bild gelöscht von #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                    elsif pc[:type] == 'upload_planung_pdf'
                        io.puts "<div class='history_entry'>Strukturplanung hochgeladen von #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                    elsif pc[:type] == 'delete_planung_pdf'
                        io.puts "<div class='history_entry'>Strukturplanung gelöscht von #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                    else
                        io.puts pc.to_json
                    end
                end
            end
            io.string
        end
    end

    post '/api/my_projekttage_history' do
        require_user!
        data = parse_request_data(
            :optional_keys => [
                :sus_email,
            ],
            :max_body_length => 16384,
            :max_string_length => 8192
        )
        sus_email = @session_user[:email]
        if teacher_logged_in?
            sus_email = data[:sus_email] if data[:sus_email]
        end
        respond(:html => my_projekttage_history(sus_email))
    end

    post '/api/update_projekttage' do
        require_user!
        data = parse_request_data(
            :optional_keys => [
                :sus_email,
                :nr,
                :name,
                :ziel,
                :teilnehmer_min,
                :teilnehmer_max,
                :klassenstufe_min,
                :klassenstufe_max,
                :grobplanung1,
                :grobplanung2,
                :grobplanung3,
                :produkt,
                :praesentationsidee,
                :material,
                :kosten_finanzierungsidee,
                :lehrkraft_wunsch,
                :raumwunsch,
                :lehrkraft,
                :raum,
                :planung_exkursion,
                :planung_tablets,
                :werbetext,
            ],
            :types => {
                :teilnehmer_min => Integer,
                :teilnehmer_max => Integer,
                :klassenstufe_min => Integer,
                :klassenstufe_max => Integer,
            },
            :max_body_length => 16384,
            :max_string_length => 8192
        )
        sus_email = @session_user[:email]
        sus_email = data[:sus_email] if data[:sus_email]
        if sus_email != @session_user[:email]
            require_teacher!
        end
        assert(email_is_projekttage_organizer?(@@user_info, sus_email))
        unless user_with_role_logged_in?(:can_manage_projekttage)
            assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        end
        ts = Time.now.to_i
        transaction do
            p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
                MATCH (u:User {email: $sus_email})
                MERGE (p:Projekttage)-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            PROJEKTTAGE_KEYS.each do |key|
                if data.include?(key)
                    value = data[key]
                    debug "#{key} => #{value}"
                    if (value || '') != (p[key] || '')
                        neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, key => value})
                            MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                            SET p.#{key.to_s} = $#{key.to_s}
                            RETURN p;
                        END_OF_QUERY
                        neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :key => key, :value => value, :ts => ts, :editor_email => @session_user[:email]})
                            MATCH (eu:User {email: $editor_email})
                            MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $sus_email})
                            CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
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
        respond(:yay => 'sure', :result => get_my_projekttage(sus_email))
    end

    def projekttage_overview_rows
        assert(teacher_logged_in? || email_is_projekttage_organizer?(@@user_info, @session_user[:email]))

        seen_sus = Set.new()
        projekttage_hash = {}
        projekttage_by_email = {}
        rows = []
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User)
            RETURN ID(p) AS id, p, u.email;
        END_OF_QUERY
            id = row['id']
            unless projekttage_hash.include?(id)
                projekttage_hash[id] = row['p']
                projekttage_hash[id][:sus] = []
            end
            projekttage_hash[id][:sus] << row['u.email']
            projekttage_by_email[row['u.email']] = id
        end

        sus_index = 0
        @@user_info.keys.each do |email|
            next unless email_is_projekttage_organizer?(@@user_info, email)
            next if seen_sus.include?(email)
            seen_sus << email
            projekttage = nil
            if projekttage_by_email[email]
                projekttage = projekttage_hash[projekttage_by_email[email]]
            end
            if projekttage
                projekttage[:sus].each do |x|
                    seen_sus << x
                end
            end
            projekttage ||= {}
            # STDERR.puts projekttage[:sus].to_yaml

            rows << {
                :email => email,
                :projekttage => projekttage,
                :sus_index => sus_index,
                :sus => (projekttage[:sus] || [email]).map { |x| @@user_info[x][:display_name] }.join(' / '),
            }
        end
        rows.sort! do |a, b|
            a[:sus] <=> b[:sus]
        end
        rows
    end

    post '/api/projekttage_overview' do
        assert(teacher_logged_in? || email_is_projekttage_organizer?(@@user_info, @session_user[:email]))

        klassen_info = nil

        rows = projekttage_overview_rows()
        rows.sort! do |a, b|
            a_nr = a[:projekttage][:nr] || ''
            b_nr = b[:projekttage][:nr] || ''
            a_sus_index = a[:sus_index]
            b_sus_index = b[:sus_index]
            a_nr.to_i == b_nr.to_i ? a_nr <=> b_nr : (a_nr.to_i == b_nr.to_i ? a_sus_index <=> b_sus_index : a_nr.to_i <=> b_nr.to_i)
        end

        if teacher_logged_in? && projekttage_phase() >= 4
            sus_for_project = {}
            neo4j_query(<<~END_OF_QUERY).each do |row|
                MATCH (u:User)-[ra:ASSIGNED_TO]->(p:Projekttage)
                OPTIONAL MATCH (u)-[rv:VOTED_FOR]->(p)
                RETURN u.email, ra, rv, p.nr;
            END_OF_QUERY
                email = row['u.email']
                next unless @@user_info[email] && @@user_info[email][:klassenstufe] >= 5 && @@user_info[email][:klassenstufe] <= 9
                nr = row['p.nr']
                sus_for_project[nr] ||= {}
                sus_for_project[nr][:count] ||= 0
                sus_for_project[nr][:count] += 1
                sus_for_project[nr][:motivation] ||= [0, 0, 0, 0]
                vote = [((row['rv'] || {})[:vote] || 0), 3].min
                sus_for_project[nr][:motivation][vote] += 1
                sus_for_project[nr][:want_swap] ||= 0
                if row['ra'][:want_swap] == true
                    STDERR.puts "User #{email} wants to swap project #{nr}"
                    sus_for_project[nr][:want_swap] += 1
                end
            end
            rows.map! do |row|
                row[:motivation] = sus_for_project[row[:projekttage][:nr]] || {}
                row
            end
            my_klasse = nil
            @@klassenleiter.each_pair do |klasse, shorthands|
                shorthands.each do |shorthand|
                    if @session_user[:shorthand] == shorthand
                        my_klasse = klasse
                    end
                end
            end
            if my_klasse
                klassen_info = {}
                klassen_info[:klasse] = my_klasse
                klassen_info[:klasse_tr] = tr_klasse(my_klasse)
                sus_info = {}
                neo4j_query(<<~END_OF_QUERY, {:emails => @@schueler_for_klasse[my_klasse]}).each do |row|
                    MATCH (u:User)-[ra:ASSIGNED_TO]->(p:Projekttage)
                    WHERE u.email IN $emails
                    WITH u, ra, p
                    OPTIONAL MATCH (u)-[rv:VOTED_FOR]->(p)
                    RETURN u.email, p.nr, p.name, p.raum, ra.want_swap, rv.vote;
                END_OF_QUERY
                    email = row['u.email']
                    nr = row['p.nr']
                    want_swap = row['ra.want_swap']
                    vote = row['rv.vote']
                    name = row['p.name']
                    raum = row['p.raum']
                    sus_info[email] = {
                        :nr => nr,
                        :want_swap => want_swap,
                        :vote => vote,
                        :name => name,
                        :raum => raum,
                    }
                end
                klassen_info[:sus] = []
                @@schueler_for_klasse[my_klasse].each do |email|
                    klassen_info[:sus] << {
                        :email => email,
                        :nr => (sus_info[email] || {})[:nr],
                        :vote => (sus_info[email] || {})[:vote],
                        :want_swap => (sus_info[email] || {})[:want_swap],
                        :display_name => @@user_info[email][:display_name],
                        :first_name => @@user_info[email][:first_name],
                        :last_name => @@user_info[email][:last_name],
                        :name => (sus_info[email] || {})[:name],
                        :raum => (sus_info[email] || {})[:raum],
                    }
                end
            end
        end

        respond(:rows => rows, :klassen_info => klassen_info)
    end

    post '/api/send_invitation_for_projekttage' do
        data = parse_request_data(:required_keys => [:sus_email, :name])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_projekttage)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = @@user_info.keys.select do |email|
            @@user_info[email][:display_name] == data[:name]
        end.first
        assert(other_email != nil)
        assert(email_is_projekttage_organizer?(@@user_info, sus_email))
        assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
                MATCH (u:User {email: $sus_email})
                MERGE (p:Projekttage)-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            rows = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                RETURN r;
            END_OF_QUERY
            assert(rows.size == 0)
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (ou:User {email: $other_email})
                CREATE (p)-[:INVITATION_FOR]->(ou)
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :ts => ts, :other_email => other_email, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
                SET c.type = 'invite_sus'
                SET c.other_email = $other_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
    end

    post '/api/delete_invitation_for_projekttage' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_projekttage)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(email_is_projekttage_organizer?(@@user_info, sus_email))
        assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            rows = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                RETURN r;
            END_OF_QUERY
            assert(rows.size > 0)
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                DELETE r;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :ts => ts, :other_email => other_email, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
                SET c.type = 'uninvite_sus'
                SET c.other_email = $other_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end

    def print_pending_projekttage_invitations_incoming(user_email)
        pending_invitations = neo4j_query(<<~END_OF_QUERY, {:email => user_email}).to_a
            MATCH (ou:User)<-[:BELONGS_TO]-(p:Projekttage)-[r:INVITATION_FOR]->(u:User {email: $email})
            RETURN ou.email, ID(p) AS id;
        END_OF_QUERY
        return '' if pending_invitations.empty?
        StringIO.open do |io|
            io.puts "<hr>"
            invitations = {}
            pending_invitations.each do |row|
                invitations[row['id']] ||= []
                invitations[row['id']] << row['ou.email']
            end
            invitations.values.each do |emails|
                io.puts "<p>Du hast eine Einladung von <strong>#{join_with_sep(emails.map { |x| @@user_info[x][:display_name]}, ', ', ' und ')}</strong> für ein gemeinsames Projekt erhalten.</p>"
                io.puts "<p>"
                io.puts "<button class='btn btn-success bu-accept-invitation' data-email='#{emails.first}'><i class='fa fa-check'></i>&nbsp;&nbsp;Einladung annehmen</button>"
                io.puts "<button class='btn btn-danger bu-reject-invitation' data-email='#{emails.first}'><i class='fa fa-times'></i>&nbsp;&nbsp;Einladung ablehnen</button>"
                io.puts "</p>"
            end
            io.puts "<hr>"
            io.string
        end
    end

    def pending_projekttage_invitations_outgoing(user_email)
        pending_invitations = neo4j_query(<<~END_OF_QUERY, {:email => user_email}).to_a
            MATCH (ou:User {email: $email})<-[:BELONGS_TO]-(p:Projekttage)-[r:INVITATION_FOR]->(u:User)
            RETURN u.email;
        END_OF_QUERY
        return '' if pending_invitations.empty?
        StringIO.open do |io|
            io.puts "<hr>"
            pending_invitations.each do |row|
                io.puts "<p>Du hast <strong>#{@@user_info[row['u.email']][:display_name]}</strong> für dein Projekt eingeladen.</p>"
                io.puts "<p>"
                io.puts "<button class='btn btn-danger bu-delete-invitation' data-email='#{row['u.email']}'><i class='fa fa-times'></i>&nbsp;&nbsp;Einladung zurücknehmen</button>"
                io.puts "</p>"
            end
            io.puts "<hr>"
            io.string
        end
    end

    post '/api/pending_projekttage_invitations_outgoing' do
        data = parse_request_data(:required_keys => [:sus_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_projekttage)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        respond(:html => pending_projekttage_invitations_outgoing(sus_email))
    end

    post '/api/accept_projekttage_invitation' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_projekttage)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(email_is_projekttage_organizer?(@@user_info, sus_email))
        assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (ou:User {email: $other_email})<-[:BELONGS_TO]-(p:Projekttage)-[r:INVITATION_FOR]->(u:User {email: $sus_email})
                DELETE r
                CREATE (p)-[:BELONGS_TO]->(u);
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email, :ts => ts, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $other_email})
                CREATE (eu)<-[:BY]-(c: ProjekttageChange)-[:TO]->(p)
                SET c.type = 'accept_invitation'
                SET c.email = $sus_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end

    post '/api/reject_projektage_invitation' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_projekttage)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(email_is_projekttage_organizer?(@@user_info, sus_email))
        assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (ou:User {email: $other_email})<-[:BELONGS_TO]-(p:Projekttage)-[r:INVITATION_FOR]->(u:User {email: $sus_email})
                DELETE r;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email, :ts => ts, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $other_email})
                CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
                SET c.type = 'reject_invitation'
                SET c.email = $sus_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end

    post '/api/send_projekttage_comment' do
        data = parse_request_data(:required_keys => [:sus_email, :comment], :max_body_length => 1024 * 1024, :max_string_length => 1024 * 1024, :max_value_lengths => {:comment => 1024 * 1024})
        sus_email = data[:sus_email]
        assert(user_with_role_logged_in?(:can_manage_projekttage))
        assert(email_is_projekttage_organizer?(@@user_info, sus_email))
        ts = Time.now.to_i
        transaction do
            neo4j_query(<<~END_OF_QUERY, {:ts => ts, :sus_email => sus_email, :comment => data[:comment], :email => @session_user[:email]})
                MATCH (tu:User {email: $email})
                WITH tu
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                CREATE (p)<-[:TO]-(c:ProjekttageChange {type: 'comment', comment: $comment, ts: $ts})-[:BY]->(tu);
            END_OF_QUERY
            emails = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email}).map { |x| x['ou.email'] }
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                WITH p
                MATCH (p)-[:BELONGS_TO]->(ou:User)
                RETURN ou.email;
            END_OF_QUERY
            session_user_email = @session_user[:email]
            deliver_mail do
                to emails
                cc @@users_for_role[:can_manage_projekttage].to_a.sort
                bcc SMTP_FROM
                from SMTP_FROM
                reply_to session_user_email

                subject "Kommentar zu deiner Projektplanung"

                StringIO.open do |io|
                    io.puts "<p>Hallo!</p>"
                    io.puts "<p>#{@@user_info[session_user_email][:display_name_official]} hat einen Kommentar zum aktuellen Planungsstand deines Projektes hinterlassen:</p>"
                    io.puts "<p>#{data[:comment].gsub('\n', '<br>')}</p>"
                    io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                    io.string
                end
            end
        end
        respond(:yay => 'sure')
    end

    post '/api/set_photo_for_project' do
        require_user!
        data = parse_request_data(:required_keys => [:photo])
        transaction do
            ts = Time.now.to_i
            neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email], :photo => data[:photo], :ts => ts})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $email})
                SET p.photo = $photo
                SET p.ts_updated = $ts
                RETURN p;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => @session_user[:email], :ts => ts})
                MATCH (eu:User {email: $sus_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
                SET c.type = 'upload_photo'
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
    end

    post '/api/delete_photo_for_project' do
        require_user!
        transaction do
            ts = Time.now.to_i
            neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email], :ts => ts})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $email})
                REMOVE p.photo
                SET p.ts_updated = $ts
                RETURN p;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => @session_user[:email], :ts => ts})
                MATCH (eu:User {email: $sus_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
                SET c.type = 'delete_photo'
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
    end

    post '/api/set_planung_pdf_for_project' do
        require_user!
        data = parse_request_data(:required_keys => [:sha1])
        assert(!teacher_logged_in?)
        transaction do
            ts = Time.now.to_i
            neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email], :sha1 => data[:sha1], :ts => ts})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $email})
                SET p.planung_pdf = $sha1
                SET p.ts_updated = $ts
                RETURN p;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => @session_user[:email], :ts => ts})
                MATCH (eu:User {email: $sus_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
                SET c.type = 'upload_planung_pdf'
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
    end

    post '/api/delete_planung_pdf_for_project' do
        require_user!
        assert(!teacher_logged_in?)
        transaction do
            ts = Time.now.to_i
            neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email], :ts => ts})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $email})
                REMOVE p.planung_pdf
                SET p.ts_updated = $ts
                RETURN p;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => @session_user[:email], :ts => ts})
                MATCH (eu:User {email: $sus_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
                SET c.type = 'delete_planung_pdf'
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
    end

    post '/api/toggle_category_for_projekttage' do
        require_user!
        transaction do
            data = parse_request_data(:required_keys => [:cat, :nr], :optional_keys => [:sus_email])
            cat = data[:cat]
            nr = data[:nr]
            sus_email = @session_user[:email]
            if teacher_logged_in?
                assert(user_with_role_logged_in?(:can_manage_projekttage))
                sus_email = data[:sus_email] if data[:sus_email]
            end
            projekt = neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => nr, :sus_email => sus_email})['p']
                MATCH (p:Projekttage {nr: $nr})-[:BELONGS_TO]->(u:User {email: $sus_email})
                RETURN p;
            END_OF_QUERY
            cats = (projekt[:categories] || '').split(',').map { |x| x.strip }
            if cats.include?(cat)
                cats.delete(cat)
            else
                cats << cat
            end
            cats.sort!
            cats.select! { |x| PROJEKTTAGE_CATEGORIES.include?(x) }
            cats = cats.join(',')
            STDERR.puts "cats: #{cats}"
            neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => nr, :cats => cats, :sus_email => sus_email})
                MATCH (p:Projekttage {nr: $nr})-[:BELONGS_TO]->(u:User {email: $sus_email})
                SET p.categories = $cats
                RETURN p;
            END_OF_QUERY
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
                MATCH (u:User)-[r:VOTED_FOR]->(p:Projekttage)
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
            ts_data = nil
            begin
                ts_data = JSON.parse(File.read("/internal/projekttage/votes/ts.json"))
            rescue
                return ''
            end
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
                next if projekt[:teilnehmer_max] == 0
                project_data = all_project_data[projekt[:nr]]
                io.puts "<tr>"
                io.puts "<td>#{projekt[:name]}</td>"
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
            io.puts "<h4>Projizierte Fehlerverteilung</h4>"
            io.puts "<p>Aus den projizierten Gruppen ergibt sich eine Fehlerverteilung. Der Fehler bei einer Projektzuordnung berechnet sich aus der Differenz zwischen dem höchsten Level, welches von einem SuS gewählt wurde und dem gewählten Level des zugeordneten Projekts. Wenn also jemand Projekt A mit drei Sternen gewählt hat und Projekt B bekommt, dass er gar nicht gewählt hat (0 Sterne), dann ist dieser Fehler 3 – kleinere Fehler sind also besser. Die Fehlerverteilung wird mit der Zeit schlechter, weil mehr SuS ihre Wahl getroffen haben.</p>"

            io.puts "<p>Bisher haben #{ts_data['email_count_voted']} von #{ts_data['email_count_total']} Schülerinnen und Schülern ihre Projekte gewählt:"
            io.puts "<div class='progress mb-3'>"
            p = ts_data['email_count_voted'] * 100 / ts_data['email_count_total']
            io.puts "<div class='bg-success progress-bar progress-bar-striped progress-bar-animated' role='progressbar' style='width: #{p}%;'>#{p.round}%</div>"
            io.puts "</div>"

            io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-sm' style='width: unset;'>"
            io.puts "<tr>"
            io.puts "<th>Fehler</th>"
            (0..3).each do |error|
                io.puts "<td style='min-width: 3.5em; text-align: center;'>#{error}</td>"
            end
            io.puts "</tr>"
            io.puts "<tr>"
            io.puts "<th>Anteil</th>"
            (0..3).each do |error|
                io.puts "<td>#{sprintf('%1.2f%%', ts_data['errors'][error] * 100.0)}</td>"
            end
            io.puts "</tr>"
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
                next if projekt[:teilnehmer_max] == 0
                io.puts "<tr>"
                io.puts "<td>#{projekt[:name]}</td>"
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

    def print_free_projekt_spots
        require_user!
        StringIO.open do |io|
            projekt_for_email = {}
            projekte = {}

            neo4j_query(<<~END_OF_QUERY).each do |row|
                MATCH (u:User)-[:ASSIGNED_TO]->(p:Projekttage)
                RETURN u.email, p.nr, p;
            END_OF_QUERY
                email = row['u.email']
                projekt_for_email[row['u.email']] = row['p.nr']
                projekte[row['p.nr']] ||= row['p']
            end

            sus_for_projekt = {}
            projekt_for_email.each_pair do |email, nr|
                sus_for_projekt[nr] ||= []
                sus_for_projekt[nr] << email
            end

            if projekttage_phase == 4
                io.puts "<h4>Falls du unzufrieden mit deinem Projekt bist</h4>"
                io.puts "<p>Wenn du lieber in ein anderes Projekt wechseln möchtest, hast du noch bis <strong>#{WEEKDAYS_LONG[Date.parse(PROJEKTWAHL_SWAP_PHASE_END).wday]}</strong>, den <strong>#{Date.parse(PROJEKTWAHL_SWAP_PHASE_END).strftime('%d')}. #{MONTHS[Date.parse(PROJEKTWAHL_SWAP_PHASE_END).strftime('%m').to_i]}</strong> um <strong>#{DateTime.parse(PROJEKTWAHL_SWAP_PHASE_END).strftime('%H:%M')} Uhr</strong> Zeit, um folgende Möglichkeiten zu probieren:"
                io.puts "<h5>Möglichkeit 1: Freie Plätze in anderen Projekten</h5>"
                io.puts "<p>Du kannst direkt in ein anderes Projekt wechseln, wenn dort noch ein Platz frei ist.</p>"
                io.puts "<div class='direct-project-swap-div'>"
                projekte.each_pair do |nr, projekt|
                    if sus_for_projekt[nr].size < projekt[:teilnehmer_max]
                        io.puts "<div class='direct-project-swap-candidate' data-nr='#{nr}'></div>"
                    end
                end
                io.puts "</div>"

                io.puts "<h5>Möglichkeit 2: Projekt-Tauschbörse</h5>"
                io.puts "<p>Wenn du mit jemandem dein Projekt tauschen möchtest (zu zweit oder mit mehreren), dann versuch es mit der Tauschbörse:</p>"
                io.puts "<a class='btn btn-success' href='/projekttauschboerse'>Projekt-Tauschbörse</a>"
            end
            io.string
        end
    end

    def print_projekttage_assignment_summary
        return '' unless teacher_logged_in?
        color_for_error = ['#4aa03f', '#fad31c', '#f4951b', '#bc2326']
        StringIO.open do |io|
            projekt_for_email = {}
            projekte = {}
            assign_results = JSON.parse(File.read('/internal/projekttage/votes/assign-result.json'))

            neo4j_query(<<~END_OF_QUERY).each do |row|
                MATCH (u:User)-[:ASSIGNED_TO]->(p:Projekttage)
                RETURN u.email, p.nr, p;
            END_OF_QUERY
                email = row['u.email']
                projekt_for_email[row['u.email']] = row['p.nr']
                projekte[row['p.nr']] ||= row['p']
            end

            sus_for_projekt = {}
            projekt_for_email.each_pair do |email, nr|
                sus_for_projekt[nr] ||= []
                sus_for_projekt[nr] << email
            end

            io.puts "<h4>Freie Plätze</h4>"
            io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-sm table-striped' style='width: unset;'>"
            io.puts "<tr>"
            io.puts "<th>Projekt</th>"
            io.puts "<th>Klasse</th>"
            io.puts "<th>Freie Plätze</th>"
            io.puts "</tr>"
            projekte.each_pair do |nr, projekt|
                if sus_for_projekt[nr].size < projekt[:teilnehmer_max]
                    io.puts "<tr>"
                    io.puts "<td>#{projekt[:name]}</td>"
                    if projekt[:klassenstufe_min] == projekt[:klassenstufe_max]
                        io.puts "<td>nur #{tr_klasse(projekt[:klassenstufe_min])}. Klasse</td>"
                    else
                        io.puts "<td>#{tr_klasse(projekt[:klassenstufe_min])}. – #{tr_klasse(projekt[:klassenstufe_max])}. Klasse</td>"
                    end
                    io.puts "<td>#{projekt[:teilnehmer_max] - sus_for_projekt[nr].size} von #{projekt[:teilnehmer_max]} frei</td>"
                    io.puts "</tr>"
                end
            end
            io.puts "</table>"
            io.puts "</div>"

            KLASSEN_ORDER.each do |klasse|
                klassenstufe = klasse.to_i
                klassenstufe = 7 if klassenstufe == 0
                next unless klassenstufe < 10
                io.puts "<h4>Klasse #{tr_klasse(klasse)}</h4>"
                io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
                io.puts "<table class='table table-sm table-striped' style='width: unset;'>"
                io.puts "<tr>"
                io.puts "<th style='text-align: right;'>Nr.</th>"
                io.puts "<th></th>"
                io.puts "<th>Name</th>"
                io.puts "<th>Projekt</th>"
                io.puts "</tr>"
                @@schueler_for_klasse[klasse].each.with_index do |email, index|
                    error = assign_results['error_for_email'][email]
                    io.puts "<tr>"
                    io.puts "<td style='text-align: right;'>#{index + 1}.</td>"
                    io.puts "<td style='text-align: center;'><span style='color: #{color_for_error[error]};'>⬤</span></td>"
                    io.puts "<td>#{@@user_info[email][:display_name]}</td>"
                    io.puts "<td>#{projekte[projekt_for_email[email]][:name]}</td>"
                    io.puts "</tr>"
                end
                io.puts "</table>"
                io.puts "</div>"
            end

            io.string
        end
    end

    post '/api/vote_for_project' do
        require_user!
        assert(user_eligible_for_projektwahl?)
        data = parse_request_data(:required_keys => [:nr, :vote], :types => {:vote => Integer})
        ts = Time.now.to_i
        data[:vote] = [data[:vote], 6].min
        if data[:vote] == 0
            neo4j_query(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email]})
                MATCH (u:User {email: $email})-[v:VOTED_FOR]->(p:Projekttage {nr: $nr})
                DELETE v;
            END_OF_QUERY
        else
            neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :ts => ts, :vote => data[:vote]})
                MATCH (u:User {email: $email})
                MATCH (p:Projekttage {nr: $nr})
                MERGE (u)-[v:VOTED_FOR]->(p)
                SET v.ts_updated = $ts
                SET v.vote = $vote
                RETURN p;
            END_OF_QUERY
        end
        trigger_stats_update('projektwahl')
        Main.update_projekttage_groups()
        Main.update_mailing_lists()
        respond(:ts => ts)
    end

    def self.assign_projects(emails, users, projects,
            projects_for_klassenstufe, total_capacity,
            votes, _votes_by_email,
            _votes_by_vote, _votes_by_project, user_info)
        votes_by_email = Hash[_votes_by_email.map { |a, b| [a, b.dup ] } ]
        votes_by_vote = Hash[_votes_by_vote.map { |a, b| [a, b.dup ] } ]
        votes_by_project = Hash[_votes_by_project.map { |a, b| [a, b.dup ] } ]
        # STDERR.puts "Got #{emails.size} emails"
        # STDERR.puts "Got #{projects.size} projects with a total capacity of #{total_capacity}"
        # STDERR.puts "Total capacity: #{total_capacity}"

        # Update 2025: Also take into account the error
        # of the previous year: if it's 2 or 3, then
        # boost the vote by (error - 1)
        last_year = PROJEKTWAHL_VOTE_END[0, 4].to_i - 1
        path = "/data/projekte/assigned-results-#{last_year}.json"
        if File.exist?(path)
            last_year_assignments = JSON.parse(File.read(path))
            error_for_email = last_year_assignments['error_for_email']
            error_for_email.each_pair do |email, error|
                if error >= 2
                    old_votes = (votes_by_email[email]) || []
                    old_votes.each do |sha1|
                        vote = votes[sha1][:vote]
                        votes_by_vote[vote].delete(sha1)
                        vote += error - 1
                        votes[sha1][:boosted_vote] = vote
                        votes_by_vote[vote] ||= Set.new()
                        votes_by_vote[vote] << sha1
                    end
                end
            end
        end
        result = {
            :project_for_email => {},
            :error_for_email => {},
            :emails_for_project => Hash[projects.map { |k, v| [k, []] } ],
        }
        current_vote = 6
        remaining_emails = Set.new(emails)
        srand()
        # STEP 1: Assign projects by priority
        loop do
            votes_by_vote[current_vote] ||= Set.new()
            while (votes_by_vote[current_vote]).empty?
                current_vote -= 1
                votes_by_vote[current_vote] ||= Set.new()
                if current_vote == 0
                    break
                end
            end
            if current_vote == 0
                break
            end
            sha1 = votes_by_vote[current_vote].to_a.sample
            vote = votes[sha1]
            nr = vote[:nr]
            email = vote[:email]
            # STDERR.puts "[#{current_vote} / #{votes_by_vote[current_vote].size} left] #{sha1} => #{vote.to_json}"
            if result[:emails_for_project][nr].size < projects[nr][:teilnehmer_max]
                # user can be assigned to project
                result[:emails_for_project][nr] << email
                if result[:project_for_email][email]
                    raise 'argh'
                end
                remaining_emails.delete(email)
                result[:project_for_email][email] = nr
                result[:error_for_email][email] = [0, users[email][:highest_vote] - current_vote].max
                # clear all entries of user
                votes_by_email[email].each do |x|
                    votes_by_vote[votes[x][:vote]].delete(x)
                    votes_by_vote[votes[x][:boosted_vote]].delete(x) if votes[x][:boosted_vote]
                end
            end
            votes_by_vote[current_vote].delete(sha1)
        end
        # STDERR.puts "Assigned #{result[:project_for_email].size} of #{emails.size} users."
        # STEP 2: Randomly assign the rest
        remaining_projects = Set.new()
        projects.each_pair do |nr, p|
            if p[:teilnehmer_max] - result[:emails_for_project][nr].size > 0
                remaining_projects << nr
            end
        end
        while !remaining_emails.empty?
            email = remaining_emails.to_a.sample
            klassenstufe = user_info[email][:klassenstufe] || 7
            pool = projects_for_klassenstufe[klassenstufe] & remaining_projects
            if pool.empty?
                raise "Oops: Cannot assign #{email} (Klassenstufe #{klassenstufe})"
            end
            nr = pool.to_a.sample
            remaining_emails.delete(email)
            if result[:project_for_email][email]
                raise 'argh'
            end
            result[:project_for_email][email] = nr
            result[:emails_for_project][nr] << email
            result[:error_for_email][email] = users[email][:highest_vote] || 0
            if result[:emails_for_project][nr].size >= projects[nr][:teilnehmer_max]
                remaining_projects.delete(nr)
            end
        end
        # STDERR.puts "Assigned #{result[:project_for_email].size} of #{emails.size} users."
        result
    end

    def print_projekt_interesse(user_email)
        projekt = nil
        neo4j_query(<<~END_OF_QUERY, {:email => user_email}).each do |row|
            MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $email})
            RETURN p;
        END_OF_QUERY
            projekt = row['p']
        end
        return '' if projekt.nil? || projekt[:klassenstufe_min].nil? || projekt[:klassenstufe_max].nil? || projekt[:teilnehmer_max].nil?

        votes = {}
        neo4j_query(<<~END_OF_QUERY, {:nr => projekt[:nr]}).each do |row|
            MATCH (u:User)-[r:VOTED_FOR]->(p:Projekttage {nr: $nr})
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
            (projekt[:klassenstufe_min]..projekt[:klassenstufe_max]).each do |klasse|
                io.puts "<th class='#{klasse == projekt[:klassenstufe_min] ? 'cbl' : ''}' style='text-align: center;'>#{klasse}.</th>"
            end
            io.puts "<th class='cbl' style='text-align: center;'>Σ</th>"
            io.puts "</tr>"
            ndash = "<span class='text-muted'>&ndash;</span>"
            [3, 2, 1].each do |vote|
                io.puts "<tr>"
                io.puts "<td>#{PROJEKT_VOTE_CODEPOINTS[vote].chr(Encoding::UTF_8)} #{PROJEKT_VOTE_LABELS[vote]}</td>"
                (projekt[:klassenstufe_min]..projekt[:klassenstufe_max]).each do |klasse|
                    count = votes["#{klasse}/#{vote}"] || ndash
                    io.puts "<td class='#{klasse == projekt[:klassenstufe_min] ? 'cbl' : ''}' style='text-align: center;'>#{count}</td>"
                end
                count = votes["vote/#{vote}"] || ndash
                io.puts "<td class='cbl' style='text-align: center;'>#{count}</td>"
                io.puts "</tr>"
            end
            io.puts "<tr>"
            io.puts "<td>Σ</td>"
            (projekt[:klassenstufe_min]..projekt[:klassenstufe_max]).each do |klasse|
                count = votes["klassenstufe/#{klasse}"] || ndash
                io.puts "<td class='#{klasse == projekt[:min_klassenstufe_minklasse] ? 'cbl' : ''}' style='text-align: center;'>#{count}</td>"
            end
            count = votes["total"] || ndash
            io.puts "<td class='cbl' style='text-align: center;'>#{count}</td>"
            io.puts "</tr>"
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
    end

    def print_projekt_interesse_stats(user_email)
        projekt = nil
        neo4j_query(<<~END_OF_QUERY, {:email => user_email}).each do |row|
            MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $email})
            RETURN p;
        END_OF_QUERY
            projekt = row['p']
        end
        return '' if projekt.nil? || projekt[:klassenstufe_min].nil? || projekt[:klassenstufe_max].nil? || projekt[:teilnehmer_max].nil?

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
            x = (5..9).select do |klasse|
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
                io.puts "<p><strong>Hinweis:</strong> Nach dem aktuellen Stand werdet ihr ca. <strong>#{data['vote']['0']} Kind#{data['vote']['0'] > 1 ? 'er' : ''}</strong> betreuen müssen, #{data['vote']['0'] > 1 ? 'die' : 'das'} (bis jetzt) keine Lust auf euer Projekt #{data['vote']['0'] > 1 ? 'haben' : 'hat'}. Falls ihr mit der Motivation eurer Gruppe nicht zufrieden seid, könnt ihr die Situation möglicherweise verbessern, indem ihr ggfs. euren Titel, euren Werbetext und / oder euer Projektbild aktualisiert oder Werbung in der Schule für euer Projekt macht. Da alle Kinder ihre Wahl noch bis <strong>#{WEEKDAYS_LONG[(Date.parse(PROJEKTWAHL_VOTE_END).strftime('%u').to_i) % 7]}, den #{Date.parse(PROJEKTWAHL_VOTE_END).strftime('%d.%m.%Y')} um #{DateTime.parse(PROJEKTWAHL_VOTE_END).strftime('%H:%M')} </strong> anpassen können, habt ihr bis dahin noch die Gelegenheit, die Zusammensetzung eurer Gruppe zu optimieren.</p>"
            end
            io.puts "<p>Bitte beachte, dass sich die Zusammensetzung deiner Gruppe noch ändern wird, abhängig vom weiteren Wahlverhalten, Umwahlen oder Anpassungen in eurem Projekt.</p>"
            io.puts "<p>Bisher haben #{ts_data['email_count_voted']} von #{ts_data['email_count_total']} Schülerinnen und Schülern ihre Projekte gewählt:"
            io.puts "<div class='progress'>"
            p = ts_data['email_count_voted'] * 100 / ts_data['email_count_total']
            io.puts "<div class='bg-success progress-bar progress-bar-striped progress-bar-animated' role='progressbar' style='width: #{p}%;'>#{p.round}%</div>"
            io.puts "</div>"
            io.puts "</p>"
            io.puts "<p>Diese folgenden Kinder haben bisher Interesse an eurem Projekt bekundet (die Prozentwerte geben an, wie hoch die Wahrscheinlichkeit momentan ist, dass sie in euer Projekt kommen):</p>"
            io.puts "<div class='name-list'>"
            data['sus'].each.with_index do |row, _|
                user_info = @@user_info[row['email']]
                io.puts "<div>#{user_info[:display_name]} (#{tr_klasse(user_info[:klasse])})<div class='info'>#{row['prob']}%</div></div>"
            end
            io.puts "</div>"
            io.string
        end
    end

    def print_projekt_assigned_sus(user_email)
        projekt = nil
        neo4j_query(<<~END_OF_QUERY, {:email => user_email}).each do |row|
            MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $email})
            RETURN p;
        END_OF_QUERY
            projekt = row['p']
        end
        return '' if projekt.nil? || projekt[:klassenstufe_min].nil? || projekt[:klassenstufe_max].nil? || projekt[:teilnehmer_max].nil?

        sus = []
        neo4j_query(<<~END_OF_QUERY, {:nr => projekt[:nr]}).each do |row|
            MATCH (u:User)-[r:ASSIGNED_TO]->(p:Projekttage {nr: $nr})
            RETURN u.email, r;
        END_OF_QUERY
            email = row['u.email']
            next unless @@user_info[email]
            next unless @@user_info[email][:roles].include?(:schueler)
            sus << email
        end
        sus.sort! do |a, b|
            ia = @@user_info[a]
            ib = @@user_info[b]
            ia[:klassenstufe] ||= 7
            ib[:klassenstufe] ||= 7
            (ia[:klassenstufe] == ib[:klassenstufe]) ?
            (ia[:klasse] <=> ib[:klasse]) :
            (ia[:klassenstufe] <=> ib[:klassenstufe])
        end

        StringIO.open do |io|
            io.puts "<p>Die folgenden Schülerinnen und Schüler nehmen an deinem Projekt teil. Unten in der Tabelle findest du E-Mail-Verteiler, die du nutzen kannst, um alle Teilnehmer:innen und / oder deren Eltern zu erreichen. Nutze deine schulische E-Mail-Adresse, um die Verteiler zu verwenden.</p>"
            if projekttage_phase() < 5
                io.puts "<p><strong>Achtung:</strong> Bitte beachte, dass momentan noch Projekte getauscht werden können. Die finale Teilnehmerliste steht erst am <strong>#{WEEKDAYS_LONG[Date.parse(PROJEKTWAHL_SWAP_PHASE_END).wday]}</strong>, den <strong>#{Date.parse(PROJEKTWAHL_SWAP_PHASE_END).strftime('%d')}. #{MONTHS[Date.parse(PROJEKTWAHL_SWAP_PHASE_END).strftime('%m').to_i]}</strong> um <strong>#{DateTime.parse(PROJEKTWAHL_SWAP_PHASE_END).strftime('%H:%M')} Uhr</strong> fest.</p>"
            elsif projekttage_phase() == 5
                io.puts "<p>Diese Teilnehmerliste ist jetzt final, es können keine Projekte mehr getauscht werden.</p>"
            end
            io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-sm' style='width: unset;'>"
            io.puts "<tr>"
            io.puts "<th>Nr.</th>"
            io.puts "<th></th>"
            io.puts "<th>Name</th>"
            io.puts "<th>Klasse</th>"
            io.puts "<th>Motivation</th>"
            io.puts "<th style='width: 30em;'>E-Mail</th>"
            io.puts "</tr>"
            sus.each.with_index do |email, i|
                this_project_vote = 0
                want_swap = false
                neo4j_query(<<~END_OF_QUERY, {:email => email, :nr => projekt[:nr]}).each do |row|
                    MATCH (u:User {email: $email})-[v:VOTED_FOR]->(p:Projekttage {nr: $nr})
                    RETURN COALESCE(v.vote, 0) AS vote;
                END_OF_QUERY
                    this_project_vote = [row['vote'], 3].min
                end
                neo4j_query(<<~END_OF_QUERY, {:email => email, :nr => projekt[:nr]}).each do |row|
                    MATCH (u:User {email: $email})-[r:ASSIGNED_TO]->(p:Projekttage {nr: $nr})
                    RETURN r.want_swap AS want_swap;
                END_OF_QUERY
                    want_swap = true if row['want_swap']
                end
                motivation = "#{PROJEKT_VOTE_CODEPOINTS[this_project_vote].chr(Encoding::UTF_8)}"
                if want_swap
                    motivation += " (möchte wechseln)"
                end
                io.puts "<tr class='user_row'>"
                io.puts "<td>#{i + 1}.</td>"
                io.puts "<td><div class='icon nav_avatar'>#{user_icon(email, 'avatar-md')}</div></td>"
                io.puts "<td>#{@@user_info[email][:display_name]}</td>"
                io.puts "<td>#{tr_klasse(@@user_info[email][:klasse])}</td>"
                io.puts "<td>#{motivation}</td>"
                io.write "<td>"
                print_email_field(io, email)
                io.write "</td>"
                io.puts "</tr>"
            end
            ['', 'eltern.'].each do |prefix|
                io.puts "<tr class='user_row'>"
                io.puts "<td colspan='5'><em>E-Mail-Verteiler: #{prefix == 'eltern.' ? 'Alle Eltern eurer Teilnehmer:innen' : 'Alle Teilnehmer:innen'}</em></td>"
                io.write "<td>"
                print_email_field(io, "#{prefix}projekt-#{projekt[:nr]}@#{MAILING_LIST_DOMAIN}")
                io.write "</td>"
                io.puts "</tr>"
            end
            io.puts "</table>"
            io.puts "</div>"

            io.string
        end
    end

    post '/api/swap_project_direct' do
        data = parse_request_data(:required_keys => [:nr])
        require_user!
        assert(user_was_eligible_for_projektwahl?)
        transaction do
            taken_spots = Set.new()
            teilnehmer_max = nil
            neo4j_query(<<~END_OF_QUERY, {:nr => data[:nr]}).each do |row|
                MATCH (u:User)-[:ASSIGNED_TO]->(p:Projekttage {nr: $nr})
                RETURN u.email, p.teilnehmer_max;
            END_OF_QUERY
                email = row['u.email']
                taken_spots << email
                teilnehmer_max ||= row['p.teilnehmer_max']
            end

            spots_left = teilnehmer_max - taken_spots.size

            assert(spots_left > 0)

            neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})
                MATCH (u:User {email: $email})-[r:ASSIGNED_TO]->(p:Projekttage)
                DELETE r
                RETURN p.nr;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email], :nr => data[:nr]})
                MATCH (u:User {email: $email}), (p:Projekttage {nr: $nr})
                CREATE (u)-[r:ASSIGNED_TO]->(p)
                SET r.swapped = true
                RETURN p.nr;
            END_OF_QUERY
        end
        Main.update_assign_result_errors()
        Main.update_mailing_lists();
        respond(:success => true)
    end

    def purge_inconsitent_swap_requests
        requests = []
        neo4j_query(<<~END_OF_QUERY, {}).each do |row|
            MATCH (u:User)-[r:WANT_PROJECT_FROM]->(o:User)
            RETURN u.email, r, o.email, ID(r) AS r_id;
        END_OF_QUERY
            requests << {
                :r_id => row['r_id'],
                :from => row['u.email'],
                :to => row['o.email'],
                :have => row['r'][:have],
                :want => row['r'][:want]
            }
        end
        current_project_for_candidates = {}
        neo4j_query(<<~END_OF_QUERY, {}).each do |row|
            MATCH (u:User)-[r:ASSIGNED_TO]->(p:Projekttage)
            WHERE r.want_swap = true
            RETURN u.email, p.nr;
        END_OF_QUERY
            current_project_for_candidates[row['u.email']] = row['p.nr']
        end
        # remove want request if:
        # - any one of both users does not have the want_swap flag in the assigned_to relationship
        # - the have or want project numbers do not match the currently assigned project IDs
        purge_ids = []
        requests.each do |request|
            if current_project_for_candidates[request[:from]] == request[:have] && current_project_for_candidates[request[:to]] == request[:want]
                next
            end
            STDERR.puts "Purging swap request: #{request[:from]} => #{request[:to]}"
            purge_ids << request[:r_id]
        end
        unless purge_ids.empty?
            neo4j_query(<<~END_OF_QUERY, {:purge_ids => purge_ids})
                MATCH (u:User)-[r:WANT_PROJECT_FROM]->(o:User)
                WHERE ID(r) IN $purge_ids
                DELETE r;
            END_OF_QUERY
        end
    end

    post '/api/get_projekt_swap_state' do
        require_user!
        assert(user_was_eligible_for_projektwahl?)
        result = {
            :want_swap => false,
            :swap_candidates => [],
        }
        purge_inconsitent_swap_requests()
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]}).each do |row|
            MATCH (u:User {email: $email})-[r:ASSIGNED_TO]->(p:Projekttage)
            RETURN r, p;
        END_OF_QUERY
            r = row['r']
            p = row['p']
            result[:want_swap] = true if r[:want_swap]
            result[:projekt] = {
                :nr => p[:nr],
                :name => p[:name],
                :teilnehmer_max => p[:teilnehmer_max],
                :klassenstufe_min => p[:klassenstufe_min],
                :klassenstufe_max => p[:klassenstufe_max],
                :werbetext => p[:werbetext],
                :photo => p[:photo],
                :organized_by => [],
            }
        end
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]}).each do |row|
            MATCH (u:User {email: $email})-[:ORGANIZED]->(p:Projekttage)-[:BELONGS_TO]->(o:User)
            RETURN o.email;
        END_OF_QUERY
            result[:projekt][:organized_by] << row['o.email']
        end

        neo4j_query(<<~END_OF_QUERY, {}).each do |row|
            MATCH (u:User)-[r:ASSIGNED_TO]->(p:Projekttage)
            WHERE r.want_swap = true
            RETURN u.email, r, p;
        END_OF_QUERY
            email = row['u.email']
            r = row['r']
            p = row['p']
            next if email == @session_user[:email]
            next if p[:klassenstufe_min] > @@user_info[@session_user[:email]][:klassenstufe]
            next if p[:klassenstufe_max] < @@user_info[@session_user[:email]][:klassenstufe]
            result[:swap_candidates] << {
                :email => email,
                :name => @@user_info[email][:display_name],
                :first_name => @@user_info[email][:first_name],
                :klasse => @@user_info[email][:klasse],
                :projekt_name => p[:name],
                :projekt_nr => p[:nr],
            }
        end
        neo4j_query(<<~END_OF_QUERY, {email: @session_user[:email]}).each do |row|
            MATCH (u:User {email: $email})-[r:WANT_PROJECT_FROM]->(o:User)
            RETURN o.email;
        END_OF_QUERY
            result[:pending_swap_request] = row['o.email']
        end
        respond(result)
    end

    post "/api/set_want_swap" do
        require_user!
        assert(user_was_eligible_for_projektwahl?)
        data = parse_request_data(:required_keys => [:want_swap])
        want_swap = data[:want_swap] == "true"
        if want_swap
            neo4j_query_expect_one(<<~END_OF_QUERY, { :email => @session_user[:email] })
                MATCH (u:User {email: $email})-[r:ASSIGNED_TO]->(p:Projekttage)
                SET r.want_swap = true
                RETURN p.nr;
            END_OF_QUERY
        else
            neo4j_query_expect_one(<<~END_OF_QUERY, { :email => @session_user[:email] })
                MATCH (u:User {email: $email})-[r:ASSIGNED_TO]->(p:Projekttage)
                REMOVE r.want_swap
                RETURN p.nr;
            END_OF_QUERY
            neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
                MATCH (u:User {email: $email})-[r:WANT_PROJECT_FROM]->(o:User)
                DELETE r;
            END_OF_QUERY
        end
    end

    post "/api/set_want_swap_partner" do
        require_user!
        assert(user_was_eligible_for_projektwahl?)
        data = parse_request_data(:required_keys => [:other])
        other_email = data[:other]
        assert(@@user_info.include?(other_email))
        response = {}
        transaction do
            # purge pending want requests
            neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
                MATCH (u:User {email: $email})-[r:WANT_PROJECT_FROM]->(o:User)
                DELETE r;
            END_OF_QUERY
            purge_inconsitent_swap_requests()
            own_nr = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})['p.nr']
                MATCH (u:User {email: $email})-[r:ASSIGNED_TO]->(p:Projekttage)
                RETURN p.nr;
            END_OF_QUERY
            other_nr = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => other_email})['p.nr']
                MATCH (u:User {email: $email})-[r:ASSIGNED_TO]->(p:Projekttage)
                RETURN p.nr;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email], :other_email => other_email, :own_nr => own_nr, :other_nr => other_nr})
                MATCH (u:User {email: $email}), (o:User {email: $other_email})
                CREATE (u)-[r:WANT_PROJECT_FROM]->(o)
                SET r.have = $own_nr
                SET r.want = $other_nr
                RETURN r;
            END_OF_QUERY
            # now check if there's a closed WANT_PROJECT_FROM loop from the session user - if yes, perform the swap
            path = []
            p = @session_user[:email]
            path << [p, own_nr]
            loop do
                p = nil
                nr = nil
                neo4j_query(<<~END_OF_QUERY, {:email => path.last.first}).each do |row|
                    MATCH (u:User {email: $email})-[r:WANT_PROJECT_FROM]->(o:User)-[:ASSIGNED_TO]->(p:Projekttage)
                    RETURN o.email, p.nr;
                END_OF_QUERY
                    p = row['o.email']
                    nr = row['p.nr']
                end
                break if p.nil?
                if p == @session_user[:email]
                    # OMG we found a loop :-D
                    STDERR.puts "Found a loop, performing swap:"
                    STDERR.puts path.to_yaml
                    path.each do |p|
                        email = p[0]
                        nr = p[1]
                        neo4j_query(<<~END_OF_QUERY, {:email => email})
                            MATCH (u:User {email: $email})-[r:ASSIGNED_TO]->(p:Projekttage)
                            DELETE r;
                        END_OF_QUERY
                        neo4j_query(<<~END_OF_QUERY, {:email => email})
                            MATCH (u:User {email: $email})-[r:WANT_PROJECT_FROM]->(o:User)
                            DELETE r;
                        END_OF_QUERY
                    end
                    path.each.with_index do |p, i|
                        email = p[0]
                        nr = path[(i + 1) % path.size][1]
                        neo4j_query(<<~END_OF_QUERY, {:email => email, :nr => nr})
                            MATCH (u:User {email: $email}), (p:Projekttage {nr: $nr})
                            CREATE (u)-[r:ASSIGNED_TO]->(p)
                            SET r.swapped = true;
                        END_OF_QUERY
                    end
                    Main.update_assign_result_errors()
                    Main.update_mailing_lists()
                    response[:swapped] = true
                    break
                end
                path << [p, nr]
            end
        end
        respond(response)
    end
end

