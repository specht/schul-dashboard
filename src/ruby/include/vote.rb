class Main < Sinatra::Base
    post '/api/create_vote' do
        raise 'not used anymore'
        # require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:title, :date, :count],
                                  :types => {:count => Integer})
        possible_codes = (0..9999).to_a
        Dir['/internal/vote/*.json'].each do |path|
            code = File.basename(path).gsub('.json', '').to_i
            possible_codes.delete(code)
        end
        code = possible_codes.sample
        if code.nil?
            respond(:error => 'nope')
            return
        end

        vote_data = {
            :token => RandomTag.generate(24),
            :title => data[:title],
            :date => data[:date],
            :count => data[:count]
        }
        File.open(sprintf('/internal/vote/%04d.json', code), 'w') { |f| f.write(vote_data.to_json) }
        neo4j_query(<<~END_OF_QUERY, :code => code, :email => @session_user[:email])
            MATCH (u:User {email: $email})
            CREATE (v:Vote {code: $code})-[:BELONGS_TO]->(u)
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/get_votes' do
        raise 'not used anymore'
        # require_teacher_or_sv!
        codes = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| x['v.code'] }
            MATCH (v:Vote)-[:BELONGS_TO]->(:User {email: $email})
            RETURN v.code;
        END_OF_QUERY
        results = codes.map do |code|
            begin
                vote_data = {}
                STDERR.puts "/api/get_votes: #{code}"
                File.open(sprintf("/internal/vote/%04d.json", code)) do |f|
                    vote_data = JSON.parse(f.read)
                end
                vote_data[:code] = code
                vote_data
            rescue
                STDERR.puts "Unable to read #{sprintf('/internal/vote/%04d.json', code)}"
                nil
            end
        end.reject { |x| x.nil? }
        results = results.sort do |a, b|
            a['date'] <=> b['date']
        end
        respond(:votes => results)
    end

    post '/api/delete_vote' do
        raise 'not used anymore'
        # require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:code],
                                  :types => {:code => Integer})
        code = data[:code]
        neo4j_query_expect_one(<<~END_OF_QUERY, :code => code, :email => @session_user[:email])
            MATCH (v:Vote {code: $code})-[:BELONGS_TO]->(u:User {email: $email})
            DETACH DELETE v
            RETURN u.email;
        END_OF_QUERY
        STDERR.puts "Deleting #{code}..."
        FileUtils::rm_f(sprintf('/internal/vote/%04d.json', code));
        FileUtils::rm_f(sprintf('/internal/vote/%04d.pdf', code));
        respond(:ok => true)
    end

    def vote_codes_from_token(vote_code, token, _count)
        raise 'not used anymore'
        count = ((_count + 20) / 4).to_i * 4
        vote_code = sprintf('%04d', vote_code)
        codes = []
        i = 0
        while codes.size < count do
            v = "#{token}#{i}"
            code = Digest::SHA1.hexdigest(v).to_i(16).to_s(10)[0, 8]
            code.insert(1, vote_code[0])
            code.insert(4, vote_code[1])
            code.insert(7, vote_code[2])
            code.insert(10, vote_code[3])
            codes << code unless codes.include?(code)
            i += 1
        end
        codes
    end

    get '/api/get_vote_pdf/*' do
        raise 'not used anymore'
        # require_teacher_or_sv!
        code = request.path.sub('/api/get_vote_pdf/', '').to_i
        neo4j_query_expect_one(<<~END_OF_QUERY, :code => code, :email => @session_user[:email])
            MATCH (v:Vote {code: $code})-[:BELONGS_TO]->(u:User {email: $email})
            RETURN v;
        END_OF_QUERY
        vote = nil
        File.open(sprintf('/internal/vote/%04d.json', code)) do |f|
            vote = JSON.parse(f.read)
        end
        codes = vote_codes_from_token(code, vote['token'], vote['count'])
        STDOUT.puts "Rendering PDF with #{codes.size} codes..."
        pdf = nil
        pdf_path = sprintf('/internal/vote/%04d.pdf', code)
        unless File.exist?(pdf_path)
            Prawn::Document::new(:page_size => 'A4', :page_layout => :landscape, :margin => [0, 0, 0, 0]) do
                y = 0
                x = 0

                codes.each.with_index do |code, _|
                    bounding_box([x * 14.85.cm + 1.cm, 180.mm - y * 10.5.cm + 10.5.cm], width: 12.85.cm, height: 8.5.cm) do
                        stroke { rectangle [0, 0], 12.85.cm, 8.5.cm }
                        bounding_box([5.mm, -5.mm], width: 11.85.cm) do
                            font_size 10

                            text "<b>Code für Online-Abstimmung #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME}</b>", inline_format: true
                            move_down 2.mm
                            text "<em>#{vote['title']} (#{vote['date'][8, 2].to_i}.#{vote['date'][5, 2].to_i}.#{vote['date'][0, 4]})</em>", inline_format: true
                            move_down 4.mm
                            if _ == 0
                                text "<b>MODERATOREN-CODE: #{code.split('').each_slice(3).to_a.map { |x| x.join('') }.join(' ')}</b>", inline_format: true
                                move_down 4.mm
                                text "Dieser Code ist <b>nicht</b> mit einem Stimmrecht verknüpft.", inline_format: true
                            else
                                text "Auf diesem Blatt finden Sie einen Code, mit dem Sie an\nOnline-Abstimmungen teilnehmen können. Ihre Stimme\nist anonym, weil Sie den Zettel selbst gewählt haben und\nsomit der Code nicht Ihrer Person zuzuordnen ist."
                                move_down 4.mm
                                text 'Um an der Abstimmung teilzunehmen, öffnen Sie bitte die folgende Webseite:'
                                move_down 4.mm
                                text "<b>#{VOTING_WEBSITE_URL}</b>", inline_format: true
                                move_down 4.mm
                                text "Geben Sie dort den Code <b>#{code.split('').each_slice(3).to_a.map { |x| x.join('') }.join(' ')}</b> ein. Oder scannen Sie den QR-Code, um automatisch angemeldet zu werden.", inline_format: true
                                move_down 4.mm
                                text "Bei Fragen zum Verfahren wenden Sie sich bitte an: #{WEBSITE_MAINTAINER_EMAIL}.", inline_format: true
                            end
                        end
                        bounding_box([98.mm, -2.mm], width: 2.cm) do
                            print_qr_code("#{VOTING_WEBSITE_URL}/?#{code}", :dot => 2, :stroke => false)
                        end

                    end
                    x += 1
                    if x >= 2
                        y += 1
                        if y >= 2
                            y = 0
                            start_new_page if _ < codes.size - 1
                        end
                        x = 0
                    end
                end
                pdf = render()
            end
            File.open(pdf_path, 'w') do |f|
                f.write(pdf)
            end
        end
#         respond_raw_with_mimetype_and_filename(pdf, 'application/pdf', "Codes #{vote['title']} #{vote['date']}.pdf")
        respond_raw_with_mimetype(File.read(pdf_path), 'application/pdf')
    end
end
