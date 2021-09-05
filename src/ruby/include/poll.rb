require 'tempfile'

class Main < Sinatra::Base
    def get_poll_run(prid, external_code = nil)
        result = {}
        if external_code && !external_code.empty?
            rows = neo4j_query(<<~END_OF_QUERY, :prid => prid)
                MATCH (u)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User)
                WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(p.deleted, false) = false AND COALESCE(pr.deleted, false) = false AND COALESCE(rt.deleted, false) = false
                RETURN u.email, pr.id, ID(u) AS unid, ID(pr) AS prnid;
            END_OF_QUERY
            invitation = rows.select do |row|
                row_code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + row['pr.id'] + row['u.email']).to_i(16).to_s(36)[0, 8]
                external_code == row_code
            end.first
            assert(!(invitation.nil?))
            result = neo4j_query_expect_one(<<~END_OF_QUERY, :prid => prid, :email => invitation['u.email'], :unid => invitation['unid'], :prnid => invitation['prnid'])
                MATCH (u)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User)
                WHERE ID(u) = {unid} AND ID(pr) = {prnid}
                MATCH (ou)-[rt2:IS_PARTICIPANT]->(pr2:PollRun {id: {prid}})-[:RUNS]->(p2:Poll)-[:ORGANIZED_BY]->(au2:User)
                WHERE COALESCE(rt2.deleted, false) = false
                RETURN u, pr, p, au.email, COUNT(ou) AS total_participants;
            END_OF_QUERY
        else
            require_user!
            result = neo4j_query_expect_one(<<~END_OF_QUERY, {:prid => prid, :email => @session_user[:email]})
                MATCH (u:User {email: {email}})-[:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User)
                WITH pr, p, au
                MATCH (ou)-[rt2:IS_PARTICIPANT]->(pr2:PollRun {id: {prid}})-[:RUNS]->(p2:Poll)-[:ORGANIZED_BY]->(au2:User)
                WHERE COALESCE(rt2.deleted, false) = false
                RETURN pr, p, au.email, COUNT(ou) AS total_participants
            END_OF_QUERY
        end
        poll = result['p'].props
        poll.delete(:items)
        poll_run = result['pr'].props
        poll_run[:items] = JSON.parse(poll_run[:items])
        return poll, poll_run, result['au.email'], result['total_participants']
    end
    
    post '/api/get_poll_run' do
        data = parse_request_data(:required_keys => [:prid], :optional_keys => [:external_code])
        prid = data[:prid]
        external_code = data[:external_code]
        poll, poll_run, organizer_email, total_participants = get_poll_run(prid, external_code)

        stored_response = nil
        if external_code && !external_code.strip.empty?
            rows = neo4j_query(<<~END_OF_QUERY, :prid => prid)
                MATCH (u)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User)
                WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(p.deleted, false) = false AND COALESCE(pr.deleted, false) = false AND COALESCE(rt.deleted, false) = false
                WITH u, pr
                MATCH (u)<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr)
                RETURN prs.response, u, pr;
            END_OF_QUERY
            results = rows.select do |row|
                row_code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + row['pr'].props[:id] + row['u'].props[:email]).to_i(16).to_s(36)[0, 8]
                external_code == row_code
            end
            unless results.empty?
                stored_response = JSON.parse(results.first['prs.response'])
            end
        else
            results = neo4j_query(<<~END_OF_QUERY, {:prid => poll_run[:id], :email => @session_user[:email]}).map { |x| x['prs.response'] }
                MATCH (u:User {email: {email}})<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr:PollRun {id: {prid}})
                RETURN prs.response
                LIMIT 1;
            END_OF_QUERY
            unless results.empty?
                stored_response = JSON.parse(results.first)
            end
        end
        stored_response ||= {}
        respond(:poll => poll, :poll_run => poll_run, :stored_response => stored_response,
                :organizer => (@@user_info[organizer_email] || {})[:display_name_official],
                :total_participants => total_participants)
    end
    
    post '/api/stop_poll_run' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:prid])
        now_date = Date.today.strftime('%Y-%m-%d')
        now_time = (Time.now - 60).strftime('%H:%M')
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:prid => data[:prid], :email => @session_user[:email], :now_date => now_date, :now_time => now_time})
            MATCH (pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(u:User {email: {email}})
            SET pr.end_date = {now_date}
            SET pr.end_time = {now_time}
            RETURN pr
        END_OF_QUERY
        poll_run = result['pr'].props
        poll_run[:items] = JSON.parse(poll_run[:items])
        respond(:prid => data[:prid], :end_date => now_date, :end_time => now_time)
    end
    
    post '/api/submit_poll_run' do
        data = parse_request_data(:required_keys => [:prid, :response],
                                  :optional_keys => [:external_code],
                                  :max_body_length => 64 * 1024,
                                  :max_string_length => 64 * 1024)
        prid = data[:prid]
        external_code = data[:external_code]
        poll, poll_run = get_poll_run(prid, external_code)
        now_s = DateTime.now.strftime('%Y-%m-%dT%H:%M:%S')
        good = true
        if now_s < "#{poll_run[:start_date]}T#{poll_run[:start_time]}:00"
            good = false
            respond(:error => 'Diese Umfrage ist noch nicht geöffnet.')
        elsif now_s > "#{poll_run[:end_date]}T#{poll_run[:end_time]}:00"
            good = false
            respond(:error => 'Diese Umfrage ist nicht mehr geöffnet.')
        end
        # validate max_checks items in response 
        response = JSON.parse(data[:response])
        poll_run[:items].each.with_index do |item, item_index|
            if item['type'] == 'checkbox' && item['max_checks']
                assert((response[item_index.to_s] || []).size <= item['max_checks'])
            end
        end
        if good
            if external_code && !external_code.empty?
                rows = neo4j_query(<<~END_OF_QUERY, :prid => prid)
                    MATCH (u)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)
                    WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(p.deleted, false) = false AND COALESCE(pr.deleted, false) = false AND COALESCE(rt.deleted, false) = false
                    RETURN id(u), pr, u;
                END_OF_QUERY
                results = rows.select do |row|
                    row_code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + row['pr'].props[:id] + row['u'].props[:email]).to_i(16).to_s(36)[0, 8]
                    external_code == row_code
                end
                neo4j_query(<<~END_OF_QUERY, {:prid => prid, :response => data[:response], :node_id => results.first['id(u)']})
                    MATCH (u)
                    WHERE id(u) = {node_id}
                    WITH u
                    MATCH (pr:PollRun {id: {prid}})
                    MERGE (u)<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr)
                    SET prs.response = {response};
                END_OF_QUERY
            else
                neo4j_query(<<~END_OF_QUERY, {:prid => prid, :response => data[:response], :email => @session_user[:email]})
                    MATCH (u:User {email: {email}})
                    MATCH (pr:PollRun {id: {prid}})
                    MERGE (u)<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr)
                    SET prs.response = {response};
                END_OF_QUERY
            end
            respond(:submitted => true)
        end
    end
    
    post '/api/hide_poll_run' do
        require_user!
        data = parse_request_data(:required_keys => [:prid])
        neo4j_query(<<~END_OF_QUERY, {:prid => data[:prid], :email => @session_user[:email]})
            MATCH (u:User {email: {email}})-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})
            SET rt.hide = true;
        END_OF_QUERY

        respond(:yay => 'sure')
    end
    
    def get_poll_run_results(prid)
        require_teacher_or_sv!
        temp = neo4j_query_expect_one(<<~END_OF_QUERY, {:prid => prid, :email => @session_user[:email]})
            MATCH (pu)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User {email: {email}})
            WHERE COALESCE(p.deleted, false) = false 
            AND COALESCE(pr.deleted, false) = false
            AND COALESCE(rt.deleted, false) = false
            RETURN au.email, pr, p, COUNT(pu) AS participant_count;
        END_OF_QUERY
        participants = neo4j_query(<<~END_OF_QUERY, {:prid => prid, :email => @session_user[:email]})
            MATCH (pu)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User {email: {email}})
            WHERE COALESCE(p.deleted, false) = false 
            AND COALESCE(pr.deleted, false) = false
            AND COALESCE(rt.deleted, false) = false
            RETURN labels(pu), pu.email, pu.name
        END_OF_QUERY
        participants = Hash[participants.map do |x|
            [x['pu.email'], x['pu.name'] || (@@user_info[x['pu.email']] || {})[:display_name] || 'NN']
        end]
        poll = temp['p'].props
        poll_run = temp['pr'].props
        poll[:organizer] = (@@user_info[temp['au.email']] || {})[:display_last_name]
        poll_run[:items] = JSON.parse(poll_run[:items])
        poll_run[:participant_count] = temp['participant_count']
        poll_run[:participants] = participants
        responses = neo4j_query(<<~END_OF_QUERY, {:prid => prid, :email => @session_user[:email]}).map { |x| {:response => JSON.parse(x['prs.response']), :email => x['u.email']} }
            MATCH (u)<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User {email: {email}})
            WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser)
            RETURN u.email, prs.response;
        END_OF_QUERY
        responses.sort! { |a, b| participants[a] <=> participants[b] }
        return poll, poll_run, responses
    end
    
    def poll_run_results_to_html(poll, poll_run, responses, target = :web, only_this_email = nil)
        StringIO.open do |io|
            unless only_this_email
                io.puts "<h3>Umfrage: #{poll[:title]}</h3>"
                io.puts "<p>Diese #{poll_run[:anonymous] ? 'anonyme' : 'personengebundene'} Umfrage wurde von #{poll[:organizer].sub('Herr ', 'Herrn ')} mit #{poll_run[:participant_count]} Teilnehmern am #{Date.parse(poll_run[:start_date]).strftime('%d.%m.%Y')} durchgeführt.</p>"
                io.puts "<div class='alert alert-info'>"
                io.puts "Von #{poll_run[:participant_count]} Teilnehmern haben #{responses.size} die Umfrage beantwortet (#{(responses.size * 100 / poll_run[:participant_count]).to_i}%)."
                unless poll_run[:anonymous]
                    missing_responses_from = (Set.new(poll_run[:participants].keys) - Set.new(responses.map { |x| x[:email]})).map { |x| poll_run[:participants][x] }.sort
                    io.puts "Es fehlen Antworten von: <em>#{missing_responses_from.join(', ')}</em>."
                end
                io.puts "</div>"
                poll_run[:items].each_with_index do |item, item_index|
                    item = item.transform_keys(&:to_sym)
                    if item[:type] == 'paragraph'
                        io.puts "<p><strong>#{item[:title]}</strong></p>" unless (item[:title] || '').strip.empty?
                        io.puts "<p>#{item[:text]}</p>" unless (item[:text] || '').strip.empty?
                    elsif item[:type] == 'radio' || item[:type] == 'checkbox'
                        io.puts "<p>"
                        io.puts "<strong>#{item[:title]}</strong>"
                        if item[:type] == 'checkbox'
                            io.puts " <em>(Mehrfachnennungen möglich)</em>"
                        end
                        io.puts "</p>"
                        histogram = {}
                        participants_for_answer = {}
                        (0...item[:answers].size).each { |x| histogram[x] = 0 }
                        responses.each do |entry|
                            response = entry[:response]
                            if item[:type] == 'radio'
                                value = response[item_index.to_s]
                                unless value.nil?
                                    unless histogram[value]
                                        STDERR.puts "Error evaluating poll: unknown value #{value} for #{item.to_json}!"
                                        next
                                    end
                                    histogram[value] += 1
                                    participants_for_answer[value] ||= []
                                    participants_for_answer[value] << entry[:email]
                                end
                            else
                                (response[item_index.to_s] || []).each do |value|
                                    unless histogram[value]
                                        STDERR.puts "Error evaluating poll: unknown value #{value} for #{item.to_json}!"
                                        next
                                    end
                                    histogram[value] += 1
                                    participants_for_answer[value] ||= []
                                    participants_for_answer[value] << entry[:email]
                                end
                            end
                        end
                        sum = histogram.values.sum
                        sum = 1 if sum == 0
                        io.puts "<table class='table'>"
                        io.puts "<tbody>"
                        (0...item[:answers].size).each do |answer_index| 
                            v = histogram[answer_index]
                            io.puts "<tr class='pb-0'><td>#{item[:answers][answer_index]}</td><td style='text-align: right;'>#{v == 0 ? '&ndash;' : v}</td></tr>"
                            io.puts "<tr class='noborder pdf-space-below'><td colspan='2'>"
                            io.puts "<div class='progress'>"
                            io.puts "<div class='progress-bar progress-bar-striped bg-info' role='progressbar' style='width: #{(v * 100.0 / sum).round}%' aria-valuenow='50' aria-valuemin='0' aria-valuemax='100'><span>#{(v * 100.0 / sum).round}%</span></div>"
                            io.puts "</div>"
                            unless poll_run[:anonymous]
                                if participants_for_answer[answer_index]
                                    io.puts "<em>#{(participants_for_answer[answer_index] || []).map { |x| poll_run[:participants][x]}.join(', ')}</em>"
                                else
                                    io.puts "<em>&ndash;</em>"
                                end
                            end
                            io.puts "</td></tr>"
                        end
                        io.puts "</tbody>"
                        io.puts "</table>"
                    elsif item[:type] == 'textarea'
                        io.puts "<p>"
                        io.puts "<strong>#{item[:title]}</strong>"
                        io.puts "</p>"
                        first_response = true
                        responses.each do |entry|
                            response = entry[:response][item_index.to_s].strip
                            unless response.empty?
                                io.puts "<hr />" unless first_response
                                if poll_run[:anonymous]
                                    io.puts "<p>#{response}</p>"
                                else
                                    io.puts "<p><em>#{poll_run[:participants][entry[:email]]}</em>: #{response}</p>"
                                end
                                first_response = false
                            end
                        end
                        
                    end
                end
            end
            unless poll_run[:anonymous]
                responses.each do |entry|
                    if only_this_email
                        next unless entry[:email] == only_this_email
                    else
                        io.puts "<div class='page-break'></div>"
                    end
                    io.puts "<h3>Einzelauswertung: #{poll_run[:participants][entry[:email]]}</h3>"
                    poll_run[:items].each_with_index do |item, item_index|
                        item = item.transform_keys(&:to_sym)
                        if item[:type] == 'paragraph'
                            io.puts "<p><strong>#{item[:title]}</strong></p>" unless (item[:title] || '').strip.empty?
                            io.puts "<p>#{item[:text]}</p>" unless (item[:text] || '').strip.empty?
                        elsif item[:type] == 'radio'
                            io.puts "<p>"
                            io.puts "<strong>#{item[:title]}</strong>"
                            io.puts "</p>"
                            answer = entry[:response][item_index.to_s]
                            unless answer.nil?
                                io.puts "<p>#{item[:answers][answer]}</p>"
                            end
                        elsif item[:type] == 'radio' || item[:type] == 'checkbox'
                            io.puts "<p>"
                            io.puts "<strong>#{item[:title]}</strong>"
                            io.puts " <em>(Mehrfachnennungen möglich)</em>"
                            io.puts "</p>"
                            unless entry[:response][item_index.to_s].nil?
                                io.puts "<p>"
                                io.puts entry[:response][item_index.to_s].reject { |x| x.nil? }.map { |answer| item[:answers][answer]}.join(', ')
                                io.puts "</p>"
                            end
                        elsif item[:type] == 'textarea'
                            io.puts "<p>"
                            io.puts "<strong>#{item[:title]}</strong>"
                            io.puts "</p>"
                            response = entry[:response][item_index.to_s].strip
                            io.puts "<p>#{response}</p>" unless response.empty?
                        end
                    end
                end
            end
            
#             cm = {}
#             citems = (0...poll_run[:items].size).select do |item_index|
#                 item = poll_run[:items][item_index].transform_keys(&:to_sym)
#                 ['radio', 'checkbox'].include?(item[:type])
#             end.map { |x| x.to_s }
#             citems.each do |a|
#                 citems.each do |b|
#                     next if a == b
#                     total = 0
#                     matches = 0
#                     responses.each do |response|
#                         # now we're looking at responses by one person to questions a and b
#                         va = response[:response][a]
#                         vb = response[:response][b]
#                         va = [va] unless va.is_a? Array
#                         vb = [vb] unless vb.is_a? Array
#                         va.each do |za|
#                             key = "#{a}/#{za}"
#                             cm[key] ||= 0
#                             cm[key] += 1
#                             vb.each do |zb|
#                                 key = "#{a}/#{za}-#{b}/#{zb}"
#                                 cm[key] ||= 0
#                                 cm[key] += 1
#                             end
#                         end
#                     end
#                 end
#             end
#             cm_final = {}
#             cm.keys.each do |k|
#                 next unless k.include?('-')
#                 match = cm[k]
#                 total = cm[k.split('-').first]
#                 cm_final[k] = match * 100.0 / total
#             end
#             
#             use_keys = cm_final.keys.select do |x|
#                 cm_final[x] >= 30.0
#             end.sort do |a, b|
#                 cm_final[b] <=> cm_final[a]
#             end
#             unless use_keys.empty?
#                 io.puts "<div class='page-break'></div>"
#                 io.puts "<h3>Korrelationen</h3>"
#                 io.puts "<table class='table'>"
#                 use_keys.each do |k|
#                     k2 = k.split('-').map { |x| x.split('/') }.flatten
#                     qa = poll_run[:items][k2[0].to_i]['title']
#                     aa = poll_run[:items][k2[0].to_i]['answers'][k2[1].to_i]
#                     qb = poll_run[:items][k2[2].to_i]['title']
#                     ab = poll_run[:items][k2[2].to_i]['answers'][k2[3].to_i]
#                     io.puts "<tr><td style='vertical-align: top;'>#{sprintf('%3d%%', cm_final[k])}</td><td><strong>#{qa}</strong><br />#{aa}<br /><strong>#{qb}</strong><br />#{ab}</td></tr>"
#                 end
#                 io.puts "</table>"
#             end
            
            io.string
        end
    end
    
    post '/api/get_poll_run_results' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:prid])
        poll, poll_run, responses = get_poll_run_results(data[:prid])
        html = poll_run_results_to_html(poll, poll_run, responses)
        respond(:html => html, :title => poll[:title], :prid => data[:prid], :anonymous => poll_run[:anonymous] || false)
    end
    
    get '/api/poll_run_results_pdf/*' do
        require_teacher_or_sv!
        prid = request.path.sub('/api/poll_run_results_pdf/', '')
        poll, poll_run, responses = get_poll_run_results(prid)
        html = poll_run_results_to_html(poll, poll_run, responses, :pdf)
        css = StringIO.open do |io|
            io.puts "<style>"
            io.puts "body { font-size: 12pt; line-height: 120%; }"
            io.puts "table { width: 100%; }"
            io.puts ".progress { width: 100%; background-color: #ccc; }"
            io.puts ".progress-bar { position: relative; background-color: #888; text-align: right; overflow: hidden; }"
            io.puts ".progress-bar span { margin-right: 0.5em; }"
            io.puts ".pdf-space-above td {padding-top: 0.2em; }"
            io.puts ".pdf-space-below td {padding-bottom: 0.2em; }"
            io.puts ".page-break { page-break-after: always; border-top: none; margin-bottom: 0; }"
            io.puts "</style>"
            io.string
        end
        c = Curl.post('http://weasyprint:5001/pdf', {:data => css + html}.to_json)
        pdf = c.body_str
#         respond_raw_with_mimetype_and_filename(pdf, 'application/pdf', "Umfrageergebnisse #{poll[:title]}.pdf")
        respond_raw_with_mimetype(pdf, 'application/pdf')
    end
    
    get '/api/poll_run_results_zip/*' do
        require_teacher_or_sv!
        prid = request.path.sub('/api/poll_run_results_zip/', '')
        poll, poll_run, responses = get_poll_run_results(prid)
        
        css = StringIO.open do |io|
            io.puts "<style>"
            io.puts "body { font-size: 12pt; line-height: 120%; }"
            io.puts "table { width: 100%; }"
            io.puts ".progress { width: 100%; background-color: #ccc; }"
            io.puts ".progress-bar { position: relative; background-color: #888; text-align: right; overflow: hidden; }"
            io.puts ".progress-bar span { margin-right: 0.5em; }"
            io.puts ".pdf-space-above td {padding-top: 0.2em; }"
            io.puts ".pdf-space-below td {padding-bottom: 0.2em; }"
            io.puts ".page-break { page-break-after: always; border-top: none; margin-bottom: 0; }"
            io.puts "</style>"
            io.string
        end
        
        file = Tempfile.new('poll')
        zip = nil
        begin
            Zip::File.open(file.path, Zip::File::CREATE) do |zipfile|
                html = poll_run_results_to_html(poll, poll_run, responses, :pdf)
                c = Curl.post('http://weasyprint:5001/pdf', {:data => css + html}.to_json)
                pdf = c.body_str
                zipfile.get_output_stream("Gesamtauswertung.pdf") do |f|
                    f.write(pdf)
                end
                unless poll_run[:anonymous]
                    responses.each do |entry|
                        email = entry[:email]
                        name = poll_run[:participants][email]
#                         poll_run[:participants][entry[:email]]
                        html = poll_run_results_to_html(poll, poll_run, responses, :pdf, email)
                        c = Curl.post('http://weasyprint:5001/pdf', {:data => css + html}.to_json)
                        pdf = c.body_str
                        zipfile.get_output_stream("Auswertung #{name}.pdf") do |f|
                            f.write(pdf)
                        end
                               
                    end
                end
            end
        ensure
            file.close
            zip = File.read(file.path)
            file.unlink
        end
                               
        respond_raw_with_mimetype_and_filename(zip, 'application/zip', "Umfrageergebnisse #{poll[:title]}.zip")
    end
    
    get '/api/poll_run_results_xlsx/*' do
        require_teacher_or_sv!
        prid = request.path.sub('/api/poll_run_results_xlsx/', '')
        poll, poll_run, responses = get_poll_run_results(prid)
        file = Tempfile.new('foo')
        result = nil
        assert(poll_run[:anonymous] == false)
        begin
            workbook = WriteXLSX.new(file.path)
            sheet = workbook.add_worksheet
            format_header = workbook.add_format({:bold => true})
            format_text = workbook.add_format({})
            sheet.write_string(0, 0, 'Nachname', format_header)
            sheet.write_string(0, 1, 'Vorname', format_header)
            sheet.write_string(0, 2, 'Klasse', format_header)
            sheet.set_column(0, 1, 16)
            sheet.set_column(2, 2, 6)
            x = 2
            response_by_email = {}
            responses.each do |response|
                email = response[:email]
                response_by_email[email] = response[:response]
            end
            participant_order = poll_run[:participants].keys.sort do |a, b|
                last_name_a = ((@@user_info[a] || {})[:last_name] || 'NN').downcase
                last_name_b = ((@@user_info[b] || {})[:last_name] || 'NN').downcase
                first_name_a = ((@@user_info[a] || {})[:first_name] || 'NN').downcase
                first_name_b = ((@@user_info[b] || {})[:first_name] || 'NN').downcase
                if last_name_a == last_name_b
                    first_name_a <=> first_name_b
                else
                    last_name_a <=> last_name_b
                end
            end
            participant_order.each.with_index do |email, index|
                sheet.write_string(index + 1, 0, (@@user_info[email] || {})[:last_name] || 'NN')
                sheet.write_string(index + 1, 1, (@@user_info[email] || {})[:first_name] || 'NN')
                sheet.write_string(index + 1, 2, (@@user_info[email] || {})[:klasse])
            end
            
            poll_run[:items].each.with_index do |item, item_index|
                next unless ['radio', 'textarea', 'checkbox'].include?(item['type'])
                x += 1
                sheet.write_string(0, x, item['title'], format_header)
                participant_order.each.with_index do |email, index|
                    next unless response_by_email[email]
                    label = nil
                    if item['type'] == 'textarea'
                        label = response_by_email[email][item_index.to_s]
                    elsif item['type'] == 'radio'
                        answer = response_by_email[email][item_index.to_s]
                        label = item['answers'][answer] if answer
                    elsif item['type'] == 'checkbox'
                        answers = response_by_email[email][item_index.to_s]
                        if answers
                            label = answers.map do |i|
                                item['answers'][i]
                            end.join(' / ')
                        end
                    end
                    sheet.write_string(index + 1, x, label)
                end
            end
            workbook.close
            result = File.read(file.path)
        ensure
            file.close
            file.unlink
        end
        respond_raw_with_mimetype_and_filename(result, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', "#{poll[:title]} – Umfrage von #{poll[:organizer]}.xlsx")
    end
    
    def sanitize_poll_items(items)
        items.map do |item|
            if item['type'] == 'radio' || item['type'] == 'checkbox'
                item['answers'].reject! { |x| x.strip.empty? }
            end
            item
        end
    end

    post '/api/save_poll' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:title, :items],
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024)
        id = RandomTag.generate(12)
        data[:items] = sanitize_poll_items(JSON.parse(data[:items])).to_json
        timestamp = Time.now.to_i
        poll = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :title => data[:title], :items => data[:items])['p'].props
            MATCH (a:User {email: {session_email}})
            CREATE (p:Poll {id: {id}, title: {title}, items: {items}})
            SET p.created = {timestamp}
            SET p.updated = {timestamp}
            CREATE (p)-[:ORGANIZED_BY]->(a)
            RETURN p;
        END_OF_QUERY
        poll = {
            :pid => poll[:id], 
            :poll => poll
        }
        respond(:ok => true, :poll => poll, :items => data[:items])
    end

    post '/api/update_poll' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:pid, :title, :items],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024)
        id = data[:pid]
        STDERR.puts "Updating poll #{id}"
        data[:items] = sanitize_poll_items(JSON.parse(data[:items])).to_json
        timestamp = Time.now.to_i
        poll = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :title => data[:title], :items => data[:items])['p'].props
            MATCH (p:Poll {id: {id}})-[:ORGANIZED_BY]->(a:User {email: {session_email}})
            SET p.updated = {timestamp}
            SET p.title = {title}
            SET p.items = {items}
            WITH DISTINCT p
            RETURN p;
        END_OF_QUERY
        poll = {
            :pid => poll[:id], 
            :poll => poll
        }
        # update timetable for affected users
        respond(:ok => true, :poll => poll, :pid => poll[:pid], :items => data[:items])
    end
    
    post '/api/delete_poll' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:pid])
        id = data[:pid]
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id)
                MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(p:Poll {id: {id}})
                SET p.updated = {timestamp}
                SET p.deleted = true
            END_OF_QUERY
        end
        # update all messages (but wait some time)
        respond(:ok => true, :pid => data[:pid])
    end
    
    post '/api/save_poll_run' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:pid, :anonymous,
                                                     :start_date, :start_time,
                                                     :end_date, :end_time, :recipients],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024)
        id = RandomTag.generate(12)
        timestamp = Time.now.to_i
        assert(['true', 'false'].include?(data[:anonymous]))
        poll_run = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :pid => data[:pid], :anonymous => (data[:anonymous] == 'true'), :start_date => data[:start_date], :start_time => data[:start_time], :end_date => data[:end_date], :end_time => data[:end_time])['pr'].props
            MATCH (p:Poll {id: {pid}})-[:ORGANIZED_BY]->(a:User {email: {session_email}})
            CREATE (pr:PollRun {id: {id}, anonymous: {anonymous}, start_date: {start_date}, start_time: {start_time}, end_date: {end_date}, end_time: {end_time}})
            SET pr.created = {timestamp}
            SET pr.updated = {timestamp}
            SET pr.items = p.items
            CREATE (pr)-[:RUNS]->(p)
            RETURN pr;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:User)
            WHERE u.email IN {recipients}
            CREATE (u)-[:IS_PARTICIPANT]->(pr);
        END_OF_QUERY
        # link external users from address book
        neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].reject {|x| @@user_info.include?(x)}, :session_email => @session_user[:email] )
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:ExternalUser {entered_by: {session_email}})
            WHERE u.email IN {recipients}
            CREATE (u)-[:IS_PARTICIPANT]->(pr);
        END_OF_QUERY
        # link external users (predefined)
#         STDERR.puts data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) }.to_yaml
        temp = neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) })
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:PredefinedExternalUser)
            WHERE u.email IN {recipients}
            CREATE (u)-[:IS_PARTICIPANT]->(pr);
        END_OF_QUERY
#         STDERR.puts temp.to_yaml
        poll_run = {
            :prid => poll_run[:id], 
            :info => poll_run,
            :recipients => data[:recipients],
        }
#         trigger_update("_poll_run_#{poll_run[:prid]}")
        respond(:ok => true, :poll_run => poll_run)
    end
    
    post '/api/update_poll_run' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:prid, :anonymous, :start_date, :start_time,
                                                     :end_date, :end_time, :recipients],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024)

        id = data[:prid]
        STDERR.puts "Updating poll run #{id}"
        timestamp = Time.now.to_i
        assert(['true', 'false'].include?(data[:anonymous]))
        poll_run = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :anonymous => (data[:anonymous] == 'true'), :start_date => data[:start_date], :start_time => data[:start_time], :end_date => data[:end_date], :end_time => data[:end_time], :recipients => data[:recipients])['pr'].props
            MATCH (pr:PollRun {id: {id}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(a:User {email: {session_email}})
            WHERE pr.anonymous = {anonymous}
            SET pr.updated = {timestamp}
            SET pr.start_date = {start_date}
            SET pr.start_time = {start_time}
            SET pr.end_date = {end_date}
            SET pr.end_time = {end_time}
            WITH DISTINCT pr
            OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(pr)
            SET r.deleted = true
            WITH DISTINCT pr
            RETURN pr;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:User)
            WHERE u.email IN {recipients}
            MERGE (u)-[r:IS_PARTICIPANT]->(pr)
            REMOVE r.deleted
        END_OF_QUERY
        # link external users from address book
        neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].reject {|x| @@user_info.include?(x)}, :session_email => @session_user[:email] )
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:ExternalUser {entered_by: {session_email}})
            WHERE u.email IN {recipients}
            MERGE (u)-[r:IS_PARTICIPANT]->(pr)
            REMOVE r.deleted
        END_OF_QUERY
        # link external users (predefined)
        neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) })
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:PredefinedExternalUser)
            WHERE u.email IN {recipients}
            MERGE (u)-[r:IS_PARTICIPANT]->(pr)
            REMOVE r.deleted
        END_OF_QUERY
        poll_run = {
            :prid => poll_run[:id], 
            :info => poll_run,
            :recipients => data[:recipients],
        }
        # update timetable for affected users
#         trigger_update("_poll_run_#{poll_run[:prid]}")
        respond(:ok => true, :poll_run => poll_run)
    end
    
    post '/api/delete_poll_run' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:prid])
        id = data[:prid]
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id)
                MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(p:Poll)<-[:RUNS]-(pr:PollRun {id: {id}})
                SET pr.updated = {timestamp}
                SET pr.deleted = true
            END_OF_QUERY
        end
        respond(:ok => true, :prid => data[:prid])
    end
    
    post '/api/get_external_invitations_for_poll_run' do
        require_teacher_or_sv!
        data = parse_request_data(:optional_keys => [:prid])
        id = data[:prid]
        invitations = {}
        invitation_requested = {}
        unless (id || '').empty?
            data = {:session_email => @session_user[:email], :id => id}
            temp = neo4j_query(<<~END_OF_QUERY, data).map { |x| {:email => x['r.email'], :invitations => x['invitations'] || [], :invitation_requested => x['invitation_requested'] } }
                MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(p:Poll)<-[:RUNS]-(pr:PollRun {id: {id}})<-[rt:IS_PARTICIPANT]-(r)
                WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND COALESCE(rt.deleted, false) = false
                RETURN r.email, COALESCE(rt.invitations, []) AS invitations, COALESCE(rt.invitation_requested, false) AS invitation_requested;
            END_OF_QUERY
            temp.each do |entry|
                invitations[entry[:email]] = entry[:invitations].map do |x|
                    Time.at(x).strftime('%d.%m.%Y %H:%M:%S')
                end
                invitation_requested[entry[:email]] = entry[:invitation_requested]
            end
        end
        respond(:invitations => invitations, :invitation_requested => invitation_requested)
    end
    
    def self.invite_external_user_for_poll_run(prid, email, session_user_email)
        STDERR.puts "Sending invitation mail for poll run #{prid} to #{email}"
        timestamp = Time.now.to_i
        data = {}
        data[:prid] = prid
        data[:email] = email
        data[:timestamp] = timestamp
        poll_run = nil
        temp = $neo4j.neo4j_query_expect_one(<<~END_OF_QUERY, data)
            MATCH (u:User)<-[:ORGANIZED_BY]-(p:Poll)<-[:RUNS]-(pr:PollRun {id: {prid}})<-[rt:IS_PARTICIPANT]-(r)
            WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND (r.email = {email}) AND COALESCE(rt.deleted, false) = false AND COALESCE(pr.deleted, false) = false AND COALESCE(p.deleted, false) = false
            RETURN pr, p, u.email;
        END_OF_QUERY
        poll_run = temp['pr'].props
        poll = temp['p'].props
        session_user = @@user_info[temp['u.email']][:display_last_name]
        code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + data[:prid] + data[:email]).to_i(16).to_s(36)[0, 8]
        deliver_mail do
            to data[:email]
            bcc SMTP_FROM
            from SMTP_FROM
            reply_to "#{@@user_info[session_user_email][:display_name]} <#{session_user_email}>"
            
            subject "Einladung zur Umfrage: #{poll[:title]}"

            StringIO.open do |io|
                io.puts "<p>Sie haben eine Einladung zu einer Umfrage erhalten.</p>"
                io.puts "<p>"
                io.puts "Eingeladen von: #{session_user}<br />"
                io.puts "Titel: #{poll[:title]}<br />"
                io.puts "Datum und Uhrzeit: #{Time.parse(poll_run[:start_date]).strftime('%d.%m.%Y')}, #{poll_run[:start_time]} &ndash; #{Time.parse(poll_run[:end_date]).strftime('%d.%m.%Y')}, #{poll_run[:end_time]}<br />"
                link = WEB_ROOT + "/p/#{data[:prid]}/#{code}"
                io.puts "</p>"
                io.puts "<p>Link zur Umfrage:<br /><a href='#{link}'>#{link}</a></p>"
                io.puts "<p>Bitte geben Sie den Link nicht weiter. Er ist personalisiert und nur im angegebenen Zeitraum gültig.</p>"
                io.string
            end
        end
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, data)
            MATCH (pr:PollRun {id: {prid}})<-[rt:IS_PARTICIPANT]-(r)
            WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND (r.email = {email}) AND COALESCE(rt.deleted, false) = false AND COALESCE(pr.deleted, false) = false
            SET rt.invitations = COALESCE(rt.invitations, []) + [{timestamp}]
            REMOVE rt.invitation_requested
        END_OF_QUERY
    end
    
    post '/api/invite_external_user_for_poll_run' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:prid, :email])
        self.class.invite_external_user_for_poll_run(data[:prid], data[:email], @session_user[:email])
        respond({})
    end

    get '/p/:prid/:code' do
        prid = params[:prid]
        code = params[:code]
        redirect "#{WEB_ROOT}/poll/#{prid}/#{code}", 302
    end
    
    def print_current_polls()
        require_user!
        today = Date.today.strftime('%Y-%m-%d')
        now = Time.now.strftime('%Y-%m-%dT%H:%M:%S')
        email = @session_user[:email]
        entries = neo4j_query(<<~END_OF_QUERY, :email => email, :today => today).map { |x| {:poll_run => x['pr'].props, :poll_title => x['p.title'], :organizer => x['a.email'], :hidden => x['hidden'] } }
            MATCH (u:User {email: {email}})-[rt:IS_PARTICIPANT]->(pr:PollRun)-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(a:User)
            WHERE COALESCE(rt.deleted, false) = false
            AND COALESCE(pr.deleted, false) = false
            AND COALESCE(p.deleted, false) = false
            AND {today} >= pr.start_date
            AND {today} <= pr.end_date
            RETURN pr, p.title, a.email, COALESCE(rt.hide, FALSE) AS hidden
            ORDER BY pr.end_date, pr.end_time;
        END_OF_QUERY
        entries.select! do |entry|
            pr = entry[:poll_run]
            now >= "#{pr[:start_date]}T#{pr[:start_time]}:00" && now <= "#{pr[:end_date]}T#{pr[:end_time]}:00"
        end
        return '' if entries.empty?
        hidden_entries = entries.select { |x| x[:hidden] }
        StringIO.open do |io|
            unless hidden_entries.empty?
                io.puts "<div class='hint hint_poll_hidden_indicator'>"
                io.puts "Ausgeblendete Umfragen: #{hidden_entries.map { |x| x[:poll_title] }.join(', ')} <a id='show_hidden_polls' href='#'>(anzeigen)</a>"
                io.puts "</div>"
            end
            entries.each.with_index do |entry, _|
                io.puts "<div class='hint hint_poll' style='#{entry[:hidden] ? 'display: none;': ''}'>"
                poll_title = entry[:poll_title]
                poll_run = entry[:poll_run]
                organizer = entry[:organizer]
                io.puts "<div style='float: left; width: 36px; height: 36px; margin-right: 15px; position: relative; top: 5px; left: 4px;'>"
                io.puts user_icon(organizer, 'avatar-fill')
                io.puts "</div>"
                io.puts "<div>#{@@user_info[organizer][:display_name_official]} hat #{teacher_logged_in? ? 'Sie' : 'dich'} zu einer Umfrage eingeladen: <strong>#{poll_title}</strong>. #{teacher_logged_in? ? 'Sie können' : 'Du kannst'} bis zum #{Date.parse(poll_run[:end_date]).strftime('%d.%m.%Y')} um #{poll_run[:end_time]} Uhr teilnehmen (die Umfrage <span class='moment-countdown' data-target-timestamp='#{poll_run[:end_date]}T#{poll_run[:end_time]}:00' data-before-label='läuft noch' data-after-label='ist vorbei'></span>).</div>"
                io.puts "<hr />"
                io.puts "<button style='white-space: nowrap;' class='float-right btn btn-success bu-launch-poll' data-poll-run-id='#{poll_run[:id]}'>Zur Umfrage&nbsp;<i class='fa fa-angle-double-right'></i></button>"
                io.puts "<div style='clear: both;'></div>"
                io.puts "</div>"
            end
            io.string
        end
    end

    post '/api/send_missing_poll_run_invitations' do
        require_teacher!
        data = parse_request_data(:required_keys => [:prid])
        id = data[:prid]
        STDERR.puts "Sending missing invitations for poll run #{id}"
        neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :id => id)
            MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(p:Poll)<-[:RUNS]-(pr:PollRun {id: {id}})<-[rt:IS_PARTICIPANT]-(u)
            WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND SIZE(COALESCE(rt.invitations, [])) = 0
            SET rt.invitation_requested = true;
        END_OF_QUERY
        trigger_send_invites()
        respond(:ok => true)
    end
    
    def gen_poll_data(path)
        result = {}
        result[:html] = ''
        parts = path.sub('/poll/', '').split('/')
        prid = parts[0]
        code = parts[1]
        assert((prid.is_a? String) && (!code.empty?))
        assert((code.is_a? String) && (!code.empty?))
        rows = neo4j_query(<<~END_OF_QUERY, :prid => prid)
            MATCH (u)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(ou:User)
            WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(pr.deleted, false) = false AND COALESCE(rt.deleted, false) = false
            RETURN pr, ou.email, u, p;
        END_OF_QUERY
        invitation = rows.select do |row|
            row_code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + row['pr'].props[:id] + row['u'].props[:email]).to_i(16).to_s(36)[0, 8]
            code == row_code
        end.first
        if invitation.nil?
            redirect "#{WEB_ROOT}/poll_not_found", 302
            return
        end
        ext_name = invitation['u'].props[:name]
        poll = invitation['p'].props
        poll_run = invitation['pr'].props
        now = "#{Date.today.strftime('%Y-%m-%d')}T#{Time.now.strftime('%H:%M')}:00"
        start_time = "#{poll_run[:start_date]}T#{poll_run[:start_time]}:00"
        end_time = "#{poll_run[:end_date]}T#{poll_run[:end_time]}:00"
        result[:organizer] = (@@user_info[invitation['ou.email']] || {})[:display_last_name]
        result[:organizer_icon] = user_icon(invitation['ou.email'], 'avatar-fill')
        result[:title] = poll[:title]
        result[:end_date] = poll_run[:end_date]
        result[:end_time] = poll_run[:end_time]
        result[:prid] = prid
        result[:code] = code
        result[:external_user_name] = ext_name
        if now < start_time
            result[:disable_launch_button] = true
            result[:html] += "Die Umfrage öffnet erst am"
            result[:html] += " #{Date.parse(poll_run[:start_date]).strftime('%d.%m.%Y')} um #{poll_run[:start_time]} Uhr (in <span class='moment-countdown' data-target-timestamp='#{poll_run[:start_date]}T#{poll_run[:start_time]}:00' data-before-label='' data-after-label=''></span>)."
        elsif now > end_time
            result[:disable_launch_button] = true
            result[:html] += "Die Umfrage ist bereits beendet."
        else
            result[:disable_launch_button] = false
            result[:html] += "Sie können noch bis zum #{Date.parse(poll_run[:end_date]).strftime('%d.%m.%Y')} um #{poll_run[:end_time]} Uhr teilnehmen (die Umfrage <span class='moment-countdown' data-target-timestamp='#{poll_run[:end_date]}T#{poll_run[:end_time]}:00' data-before-label='läuft noch' data-after-label='ist vorbei'></span>)."
        end
        result
    end
end
