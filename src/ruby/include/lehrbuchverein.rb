if File.exist?('/data/bibliothek/config.rb')
    require '/data/bibliothek/config.rb'
end

class Main < Sinatra::Base
    def self.determine_lehrmittelverein_state_for_all()
        @@lehrmittelverein_state_cache = {}
        @@user_info.each_pair do |email, info|
            @@lehrmittelverein_state_cache[email] = info[:teacher]
        end
        temp = $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| { :email => x['u.email'] } }
            MATCH (u:User {lmv_no_pay: true})
            RETURN u.email;
        END_OF_QUERY
        temp.each do |row|
            email = row[:email]
            @@lehrmittelverein_state_cache[email] = true
        end
        temp = $neo4j.neo4j_query(<<~END_OF_QUERY, {:jahr => LEHRBUCHVEREIN_JAHR}).map { |x| { :email => x['u.email'] } }
            MATCH (u:User)-[:PAID_FOR]->(j:Lehrbuchvereinsjahr {jahr: $jahr})
            RETURN u.email;
        END_OF_QUERY
        temp.each do |row|
            email = row[:email]
            @@lehrmittelverein_state_cache[email] = true
        end
    end

    # returns bits 1 for paid, 2 for zahlungsbefreit, 4 for lehrmittelfreiheit
    def determine_lehrmittelverein_state_for_email(email)
        result = 0
        temp = neo4j_query(<<~END_OF_QUERY, {:email => email})
            MATCH (u:User {email: $email, lmv_no_pay: true})
            RETURN u.email;
        END_OF_QUERY
        result += 2 if temp.size > 0
        # result += 4 if [5, 6].include?(((@@user_info[email] || {})[:klasse] || '').to_i)
        temp = neo4j_query(<<~END_OF_QUERY, {:email => email, :jahr => LEHRBUCHVEREIN_JAHR})
            MATCH (u:User {email: $email})-[:PAID_FOR]->(j:Lehrbuchvereinsjahr {jahr: $jahr})
            RETURN u.email;
        END_OF_QUERY
        result += 1 if temp.size > 0
        return result
    end

    post '/api/toggle_lehrbuchverein_no_pay' do
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        assert(can_manage_bib_members_logged_in?)
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email])
            MATCH (u:User {email: $email})
            SET u.lmv_no_pay = NOT COALESCE(u.lmv_no_pay, FALSE)
            RETURN u.lmv_no_pay;
        END_OF_QUERY
        @@lehrmittelverein_state_cache[email] = determine_lehrmittelverein_state_for_email(email)
        Main.update_lehrbuchverein_groups()
        Main.update_mailing_lists()
        respond(:ok => true, :state => determine_lehrmittelverein_state_for_email(email))
    end

    post '/api/toggle_lehrbuchverein_paid' do
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        assert(can_manage_bib_members_logged_in?)
        paid = neo4j_query(<<~END_OF_QUERY, {:jahr => LEHRBUCHVEREIN_JAHR, :email => data[:email]}).size > 0
            MATCH (u:User {email: $email})-[:PAID_FOR]->(j:Lehrbuchvereinsjahr {jahr: $jahr})
            RETURN u.email;
        END_OF_QUERY
        if paid
            neo4j_query(<<~END_OF_QUERY, {:jahr => LEHRBUCHVEREIN_JAHR, :email => data[:email]}).size
                MATCH (u:User {email: $email})-[r:PAID_FOR]->(j:Lehrbuchvereinsjahr {jahr: $jahr})
                DELETE r;
            END_OF_QUERY
            @@lehrmittelverein_state_cache[email] = determine_lehrmittelverein_state_for_email(email)
            Main.update_lehrbuchverein_groups()
            Main.update_mailing_lists()
            respond(:ok => true, :state => determine_lehrmittelverein_state_for_email(email))
        else
            result = neo4j_query_expect_one(<<~END_OF_QUERY, :jahr => LEHRBUCHVEREIN_JAHR, :email => data[:email])
                MATCH (u:User {email: $email})
                MERGE (j:Lehrbuchvereinsjahr {jahr: $jahr})
                CREATE (u)-[:PAID_FOR]->(j)
                RETURN u.lehrbuchverein_mitglied;
            END_OF_QUERY
            @@lehrmittelverein_state_cache[email] = determine_lehrmittelverein_state_for_email(email)
            Main.update_lehrbuchverein_groups()
            Main.update_mailing_lists()
            respond(:ok => true, :state => determine_lehrmittelverein_state_for_email(email))
        end
    end

    post '/api/get_lehrbuchverein_data' do
        assert(can_manage_bib_members_logged_in?)
        temp = neo4j_query(<<~END_OF_QUERY).map { |x| { :email => x['u.email'] } }
            MATCH (u:User {lmv_no_pay: true})
            RETURN u.email;
        END_OF_QUERY
        no_pay = Set.new()
        temp.each do |row|
            no_pay << row[:email]
        end
        temp = neo4j_query(<<~END_OF_QUERY, {:jahr => LEHRBUCHVEREIN_JAHR}).map { |x| { :email => x['u.email'] } }
            MATCH (u:User)-[:PAID_FOR]->(j:Lehrbuchvereinsjahr {jahr: $jahr})
            RETURN u.email;
        END_OF_QUERY
        paid = Set.new()
        temp.each do |row|
            paid << row[:email]
        end
        users = []
        all_schueler = []
        @@klassen_order.each do |klasse|
            (@@schueler_for_klasse[klasse] || []).each do |email|
                all_schueler << email
            end
        end
        all_schueler.each do |email|
            users << {
                :email => email,
                :last_name => @@user_info[email][:last_name],
                :first_name => @@user_info[email][:first_name],
                :klasse => tr_klasse(@@user_info[email][:klasse]),
                :klassen_index => @@klassen_index[@@user_info[email][:klasse]] || -1,
                :no_pay => no_pay.include?(email),
                :paid => paid.include?(email),
            }
        end
        respond(:users => users, :year => LEHRBUCHVEREIN_JAHR)
    end

    post '/api/upload_schulbuchverein_bank_statement' do
        require_user_with_role!(:schulbuchverein)
        file = params['file']
        filename = file['filename']
        assert(!filename.include?('/'))
        assert(filename.size > 0)
        blob = file['tempfile'].read
        blob.force_encoding('UTF-8')
        headers = nil
        # Einnahmen, die nicht verarbeitet werden konnten
        # Einnahmen, die verarbeitet wurden
        # Einnahmen, die schon verarbeitet waren
        result = {
            :entries => {},
            :skipped => [],
            :handled => [],
            :previously_handled => [],
            :extra_info => {},
        }
        token_catalogue = YAML.load(File.read("/internal/bibliothek/out/token_catalogue-#{LBV_NEXT_SCHULJAHR.gsub('/', '-')}.yaml"))
        blob.split("\n").each do |line|
            line.strip!
            parts = line.split(';').map { |x| x.strip }
            STDERR.puts "[#{parts.size}] #{parts.join(' / ')}"
            if parts.size == 18
                if headers.nil?
                    headers = parts.each_with_index.to_h
                    assert(headers['Buchungstag'])
                    assert(headers['Begünstigter / Auftraggeber'])
                    assert(headers['Verwendungszweck'])
                    assert(headers['Betrag'])
                else
                    subject = parts[headers['Verwendungszweck']]
                    amount = parts[headers['Betrag']].strip
                    # Ausgaben überspringen, uns interessieren nur die Einnahmen
                    next if amount[0] == '-'
                    datum = parts[headers['Buchungstag']]
                    from = parts[headers['Begünstigter / Auftraggeber']]
                    amount_cents = (amount.sub(',', '.').to_f * 100).to_i
                    STDERR.puts "[#{datum}] #{amount_cents} ==> #{subject} (#{from})"
                    key = "#{datum}/#{from}/#{amount_cents}/#{subject}"
                    sha1 = Digest::SHA1.hexdigest(key)
                    result[:entries][sha1] = {:datum => datum, :amount => amount_cents, :subject => subject, :from => from}
                    m = subject.upcase.strip.gsub('  ', ' ').match(/([A-Z]{2})[^A-Z]?([A-Z]{2})[^A-Z]?(\d{3})/)
                    state = :skipped
                    if m
                        token = "#{m[1]}-#{m[2]}-#{m[3]}"
                        STDERR.puts "GOT TOKEN! [#{token}]"
                        if token_catalogue[token]
                            STDERR.puts "ALSO FOUND EMAIL FOR TOKEN: #{token_catalogue[token].to_json}"
                            email = token_catalogue[token][:email]
                            if amount_cents == token_catalogue[token][:amount]
                                if @@user_info[email]
                                    $neo4j.neo4j_query(<<~END_OF_QUERY, {:email => email, :jahr => LBV_NEXT_SCHULJAHR.to_i})
                                        MATCH (u:User {email: $email})
                                        MERGE (j:Lehrbuchvereinsjahr {jahr: $jahr})
                                        CREATE (u)-[:PAID_FOR]->(j)
                                        RETURN u.lehrbuchverein_mitglied;
                                    END_OF_QUERY
                                    state = :handled
                                    result[:extra_info][sha1] = {
                                        :display_name => @@user_info[email][:display_name],
                                        :klasse => @@user_info[email][:klasse],
                                    }
                                else
                                    result[:extra_info][sha1] = {:reason => :unknown_sus, :email => email}
                                end
                            else
                                result[:extra_info][sha1] = {:reason => :unexpected_amount, :expected_amount => token_catalogue[token][:amount]}
                            end
                        else
                            result[:extra_info][sha1] = {:reason => :unknown_token}
                        end
                    else
                        result[:extra_info][sha1] = {:reason => :no_token_found}
                    end
                    result[state] << sha1
                end
            end
        end
        assert(!headers.nil?)
        Main.determine_lehrmittelverein_state_for_all()
        Main.update_lehrbuchverein_groups()
        Main.update_mailing_lists()
        respond(:uploaded => 'yeah', :result => result)
    end
end
