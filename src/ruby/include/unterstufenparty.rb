class Main < Sinatra::Base

    # For the Unterstufenparty we store a card_sha1
    # for each user, or, alternatively, a card_text
    # per User.

    def up_sus_eligible_for_party?(email)
        info = @@user_info[email]
        return false unless info[:roles].include?(:schueler)
        stufe = info[:klassenstufe]
        return stufe >= 5 && stufe <= 6
    end

    def up_sus_list
        @@user_info.keys.select do |email|
            up_sus_eligible_for_party?(email)
        end.map do |email|
            {
                :email => email,
                :display_name => @@user_info[email][:display_name],
                :first_name => @@user_info[email][:first_name],
                :klasse => @@user_info[email][:klasse],
                :code => up_code_for_email(email),
            }
        end
    end

    post '/api/up_upload_image' do
        require_user_with_role!(:unterstufenparty)
        entry = params['card']
        filename = entry['filename']
        blob = entry['tempfile'].read
        sha1 = Digest::SHA1.hexdigest(blob)
        path = "/raw/uploads/images/unterstufenparty/#{sha1}.#{filename.split('.').last}"
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, 'w') do |f|
            f.write(blob)
        end
        respond(:uploaded => 'yeah', :sha1 => sha1)
    end

    post '/api/up_get_info_for_email' do
        require_user_with_role!(:unterstufenparty)
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        events = []
        last_checkin = nil
        last_checkout = nil
        last_card_sha1 = nil
        last_card_text = nil
        last_status = nil
        neo4j_query(<<~END_OF_QUERY, {:email => email, :upid => UNTERSTUFEN_PARTY_ID}).each do |row|
            MATCH (u:User {email: $email})-[r:LOG]->(up:Unterstufenparty {id: $upid})
            RETURN r
            ORDER BY r.timestamp ASC;
        END_OF_QUERY
            events << row['r']
            case row['r'][:type]
            when 'checkin'
                last_checkin = row['r'][:timestamp]
                last_status = :checked_in
            when 'checkout'
                last_checkout = row['r'][:timestamp]
                last_status = :checked_out
            when 'set_card_sha1'
                last_card_sha1 = row['r'][:card_sha1]
            when 'set_card_text'
                last_card_text = row['r'][:card_text]
            end
        end
        result = {
            :email => email,
            :events => events,
            :last_status => last_status,
            :last_checkin => last_checkin,
            :last_checkout => last_checkout,
            :last_card_sha1 => last_card_sha1,
            :last_card_text => last_card_text,
        }
        respond(result)
    end

    post '/api/up_get_checked_in_sus' do
        require_user_with_role!(:unterstufenparty)
        checked_in_sus = Set.new()
        neo4j_query(<<~END_OF_QUERY, {:upid => UNTERSTUFEN_PARTY_ID}).each do |row|
            MATCH (u:User)-[r:LOG]->(up:Unterstufenparty {id: $upid})
            RETURN r, u
            ORDER BY r.timestamp ASC;
        END_OF_QUERY
            email = row['u'][:email]
            log = row['r']
            if log[:type] == 'checkin'
                checked_in_sus.add(email)
            elsif log[:type] == 'checkout'
                checked_in_sus.delete(email)
            end
        end
        sorted_sus = checked_in_sus.to_a.sort do |a, b|
            @@user_info[a][:first_name] <=> @@user_info[b][:first_name]
        end
        respond(:checked_in_sus => sorted_sus)
    end

    post '/api/up_checkin' do
        require_user_with_role!(:unterstufenparty)
        data = parse_request_data(:required_keys => [:email, :card_sha1, :card_text])
        email = data[:email]
        card_sha1 = data[:card_sha1]
        card_text = data[:card_text]
        timestamp = Time.now.to_i
        neo4j_query(<<~END_OF_QUERY, {:email => email, :upid => UNTERSTUFEN_PARTY_ID, :timestamp => timestamp, :card_sha1 => card_sha1, :card_text => card_text})
            MATCH (u:User {email: $email})
            MERGE (up:Unterstufenparty {id: $upid})
            CREATE (u)-[r:LOG]->(up)
            SET r.type = 'checkin'
            SET r.timestamp = $timestamp;
        END_OF_QUERY
        if card_sha1 && card_sha1 != ''
            neo4j_query(<<~END_OF_QUERY, {:email => email, :upid => UNTERSTUFEN_PARTY_ID, :card_sha1 => card_sha1, :timestamp => timestamp})
                MATCH (u:User {email: $email})
                MATCH (up:Unterstufenparty {id: $upid})
                CREATE (u)-[r:LOG]->(up)
                SET r.type = 'set_card_sha1'
                SET r.card_sha1 = $card_sha1
                SET r.timestamp = $timestamp;
            END_OF_QUERY
        end
        if card_text && card_text != ''
            neo4j_query(<<~END_OF_QUERY, {:email => email, :upid => UNTERSTUFEN_PARTY_ID, :card_text => card_text, :timestamp => timestamp})
                MATCH (u:User {email: $email})
                MATCH (up:Unterstufenparty {id: $upid})
                CREATE (u)-[r:LOG]->(up)
                SET r.type = 'set_card_text'
                SET r.card_text = $card_text
                SET r.timestamp = $timestamp;
            END_OF_QUERY
        end
        respond(:checked_in => 'yeah')
    end

    post '/api/up_checkout' do
        require_user_with_role!(:unterstufenparty)
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        timestamp = Time.now.to_i
        neo4j_query(<<~END_OF_QUERY, {:email => email, :upid => UNTERSTUFEN_PARTY_ID, :timestamp => timestamp})
            MATCH (u:User {email: $email})
            MERGE (up:Unterstufenparty {id: $upid})
            CREATE (u)-[r:LOG]->(up)
            SET r.type = 'checkout'
            SET r.timestamp = $timestamp;
        END_OF_QUERY
        respond(:checked_out => 'yeah')
    end

    get '/api/up_card_image/:sha1' do
        require_user_with_role!(:unterstufenparty)
        sha1 = params['sha1']
        path = "/raw/uploads/images/unterstufenparty/#{sha1}.jpg"
        respond_raw_with_mimetype(File.read(path), 'image/jpeg')
    end
end
