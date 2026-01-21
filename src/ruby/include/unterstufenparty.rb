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
        email = @session_user[:email]
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => email})
            MATCH (u:User {email: $email})
            RETURN u.card_sha1 AS card_sha1,
            u.card_text AS card_text,
            u.up_checked_in AS up_checked_in,
            u.up_checked_out AS up_checked_out;
        END_OF_QUERY
        result = {
            :email => email,
            :card_sha1 => result[:card_sha1],
            :card_text => result[:card_text],
            :up_checked_in => result[:up_checked_in],
            :up_checked_out => result[:up_checked_out]
        }
        respond(result)
    end
end
