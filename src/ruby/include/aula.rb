class Main < Sinatra::Base

    def self.get_aula_events
        results = $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| x['e'] }
            MATCH (e:AulaEvent)
            RETURN e
            ORDER BY toInteger(e.number), e.title;
        END_OF_QUERY
        results
    end
    
    post '/api/get_aula_events' do
        require_user_who_can_manage_tablets!
        respond(:events => self.class.get_aula_events())
    end

    post '/api/set_light_aula_event' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:id, :desk_array])
        desk_array = data[:desk_array].split(',').map { |s| s.to_i }
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :desk_array => desk_array)
            MATCH (e:AulaEvent {id: $id})
            SET e.desk_array = $desk_array;
        END_OF_QUERY
    end
    
    post '/api/delete_aula_event' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:id])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id])
            MATCH (e:AulaEvent {id: $id})
            DELETE e;
        END_OF_QUERY
        respond(:result => 'lefromage')
    end

    post '/api/clear_aula_events' do
        require_user_who_can_manage_tablets!
        neo4j_query(<<~END_OF_QUERY)
            MATCH (e:AulaEvent)
            DELETE e;
        END_OF_QUERY
        respond(:result => 'lefromage')
    end

    post '/api/finish_aula_event' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:id])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id])
            MATCH (e:AulaEvent {id: $id})
            SET e.finished = true;
        END_OF_QUERY
        respond(:result => 'lefromage')
    end
    
    post '/api/unfinish_aula_event' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:id])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id])
            MATCH (e:AulaEvent {id: $id})
            SET e.finished = false;
        END_OF_QUERY
        respond(:result => 'lefromage')
    end

    post '/api/change_aula_event_number' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:id, :number])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :number => data[:number])
            MATCH (e:AulaEvent {id: $id})
            SET e.number = $number;
        END_OF_QUERY
        respond(:result => 'lefromage')
    end
    
    post '/api/change_aula_event_time' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:id, :time])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :time => data[:time])
            MATCH (e:AulaEvent {id: $id})
            SET e.time = $time;
        END_OF_QUERY
        respond(:result => 'lefromage')
    end
    
    post '/api/change_aula_event_title' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:id, :title])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :title => data[:title])
            MATCH (e:AulaEvent {id: $id})
            SET e.title = $title;
        END_OF_QUERY
        respond(:result => 'lefromage')
    end

    post '/api/create_aula_event' do
        require_user_who_can_manage_tablets!
        id = RandomTag.generate()
        neo4j_query(<<~END_OF_QUERY, :id => id)
            CREATE (e:AulaEvent)
            SET e.id = $id
            SET e.time = ''
            SET e.title = ''
            SET e.finished = false;
        END_OF_QUERY
        respond(:result => 'lefromage')
    end

    # get '/api/aula_event_pdf' do
    #     require_user_who_can_manage_tablets!
    #     # number = 
    #     # time = 
    #     # title =
    #     events = $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| x['e'] }
    #         MATCH (e:AulaEvent)
    #         RETURN e
    #         ORDER BY e.number, e.title;
    #     END_OF_QUERY
    #     doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :portrait, 
    #                             :margin => 0) do
    #         font('/app/fonts/RobotoCondensed-Regular.ttf') do
    #             font_size 12
    #             y = 297.mm - 20.mm - 20.7.pt
    #             draw_text "Nummer", :at => [20.mm, y + 6.pt]
    #             draw_text "Zeitpunkt", :at => [40.mm, y + 6.pt]
    #             draw_text "Beschreibung", :at => [60.mm, y + 6.pt]
    #             line_width 0.4.mm
    #             stroke { line [20.mm, y], [190.mm, y] }
    #         end
    #     end
    #     respond_raw_with_mimetype(doc.render, 'application/pdf')
    # end

    get '/api/aula_event_pdf' do
        require_user_who_can_manage_tablets!
        results = $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| x['e'] }
            MATCH (e:AulaEvent)
            RETURN e
            ORDER BY toInteger(e.number), e.title;
        END_OF_QUERY
        time = Time.new
        pdf = StringIO.open do |io|
            io.puts "<style>"
            io.puts "body { font-family: Roboto; font-size: 12pt; line-height: 120%; }"
            io.puts "table { border-collapse: collapse; width: 100%; }"
            io.puts "td, th { border: 1px solid #dddddd; text-align: left; padding: 8px; }"
            io.puts ".pdf-space-above td {padding-top: 0.2em; }"
            io.puts ".pdf-space-below td {padding-bottom: 0.2em; }"
            io.puts ".page-break { page-break-after: always; border-top: none; margin-bottom: 0; }"
            io.puts "</style>"
            io.puts "<h1>Ablauf Aula</h1>"
            io.puts "<br>"
            io.puts "<table>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th style='width: 100px;'>Reihenfolge</th>"
            io.puts "<th style='width: 100px;'>Zeitunkt (geplant)</th>"
            io.puts "<th style='width: 400px;'>Beschreibung</th>"
            # io.puts "<th style='width: 120px;'>Fertig?</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            for event in results do
                io.puts "<tr>"
                io.puts "<td>#{event[:number]}</td>"
                io.puts "<td>#{event[:time]}</td>"
                io.puts "<td>#{event[:title]}</td>"
                # io.puts "<td>#{finished}</td>"
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            # io.puts "#{results}"
            # io.puts time.day
            # io.puts "."
            # io.puts time.month
            # io.puts "."
            # io.puts time.year
            io.string
        end
        c = Curl.post('http://weasyprint:5001/pdf', {:data => pdf}.to_json)
        pdf = c.body_str
        respond_raw_with_mimetype(pdf, 'application/pdf')
    end

    # post '/api/create_aula_lights' do
    #     require_user_who_can_manage_tablets!
    #     data = parse_request_data(:required_keys => [:dmx, :number])
    #     neo4j_query(<<~END_OF_QUERY, :dmx => data[:dmx], :desk => data[:desk])
    #         CREATE (e:AulaLight)
    #         SET e.dmx = $dmx
    #     END_OF_QUERY
    #     respond(:result => 'lefromage')
    # end

    def print_light_structure()
        require_user_who_can_manage_tablets!
        file_path = "/internal/aula_light/current_config.txt"

        if File.exist?(file_path)
            current_config = File.read(file_path)
        else
            current_config = ""
        end
        
        StringIO.open do |io|
            io.puts "#{current_config}"
            io.string
        end
    end

    post '/api/set_light_structure' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:structure_input], :max_body_length => 1024 * 1024, :max_string_length => 1024 * 1024, :max_value_lengths => {:structure_input => 1024 * 1024})
        File.write("/internal/aula_light/current_config.txt", data[:structure_input])
        respond(:result => 'lefromage')
    end

    post '/api/set_desk_number' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:dmx, :desk])
        if data[:desk] == ""
            neo4j_query(<<~END_OF_QUERY, :dmx => data[:dmx], :desk => data[:desk])
                MATCH (e:AulaLight {dmx: $dmx})
                DELETE e   
            END_OF_QUERY
        else
            neo4j_query(<<~END_OF_QUERY, :dmx => data[:dmx], :desk => data[:desk])
                MERGE (e:AulaLight {dmx: $dmx})
                SET e.dmx = $dmx
                SET e.desk = $desk;
            END_OF_QUERY
        end
        respond(:result => 'lefromage')
    end

    post '/api/get_light' do
        require_user_who_can_manage_tablets!
        results = $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| {:lightdata=> x['v']} }
            MATCH (v:AulaLight)
            RETURN v
        END_OF_QUERY
        respond(:light => results)
    end

    post '/api/get_light_data' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:dmx])
        results = $neo4j.neo4j_query(<<~END_OF_QUERY, :dmx => data[:dmx]).map { |x| {:lightdata=> x['v']} }
            MATCH (v:AulaLight {dmx: $dmx})
            RETURN v
        END_OF_QUERY
        if results != []
            respond(:light => results)
        end
    end
end
