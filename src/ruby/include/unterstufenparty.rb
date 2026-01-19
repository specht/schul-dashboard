class Main < Sinatra::Base
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
        STDERR.puts params.to_yaml
        entry = params['card']
        filename = entry['filename']
        blob = entry['tempfile'].read
        sha1 = Digest::SHA1.hexdigest(blob)
        path = "/raw/uploads/images/unterstufenparty/#{sha1}.#{filename.split('.').last}"
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, 'w') do |f|
            f.write(blob)
        end
        respond(:uploaded => 'yeah')
    end
end
