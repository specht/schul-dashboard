class Main < Sinatra::Base

    def self.get_aula_events
        results = $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| x['e'] }
            MATCH (e:AulaEvent)
            RETURN e
            ORDER BY e.number, e.title;
        END_OF_QUERY
        results
    end
    
    post '/api/get_aula_events' do
        require_technikteam!
        respond(:events => self.class.get_aula_events())
    end
    
    post '/api/delete_aula_event' do
        require_technikteam!
        data = parse_request_data(:required_keys => [:id])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id])
            MATCH (e:AulaEvent {id: $id})
            DELETE e;
        END_OF_QUERY
        respond(:result => 'yay')
    end

    post '/api/clear_aula_events' do
        require_technikteam!
        neo4j_query(<<~END_OF_QUERY)
            MATCH (e:AulaEvent)
            DELETE e;
        END_OF_QUERY
        respond(:result => 'yay')
    end

    post '/api/finish_aula_event' do
        require_technikteam!
        data = parse_request_data(:required_keys => [:id])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id])
            MATCH (e:AulaEvent {id: $id})
            SET e.finished = true;
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/unfinish_aula_event' do
        require_technikteam!
        data = parse_request_data(:required_keys => [:id])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id])
            MATCH (e:AulaEvent {id: $id})
            SET e.finished = false;
        END_OF_QUERY
        respond(:result => 'yay')
    end

    post '/api/change_aula_event_number' do
        require_technikteam!
        data = parse_request_data(:required_keys => [:id, :number])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :number => data[:number])
            MATCH (e:AulaEvent {id: $id})
            SET e.number = $number;
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/change_aula_event_time' do
        require_technikteam!
        data = parse_request_data(:required_keys => [:id, :time])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :time => data[:time])
            MATCH (e:AulaEvent {id: $id})
            SET e.time = $time;
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/change_aula_event_title' do
        require_technikteam!
        data = parse_request_data(:required_keys => [:id, :title])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :title => data[:title])
            MATCH (e:AulaEvent {id: $id})
            SET e.title = $title;
        END_OF_QUERY
        respond(:result => 'yay')
    end

    post '/api/create_aula_event' do
        require_technikteam!
        id = RandomTag.generate()
        neo4j_query(<<~END_OF_QUERY, :id => id)
            CREATE (e:AulaEvent)
            SET e.id = $id
            SET e.time = ''
            SET e.title = ''
            SET e.finished = false;
        END_OF_QUERY
        respond(:result => 'yay')
    end

    # get '/api/aula_event_pdf' do
    #     require_technikteam!
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

    # get '/api/aula_event_pdf' do
    #     require_technikteam!
    #     pdf = StringIO.open do |io|
    #         io.puts "<style>"
    #         io.puts "body { font-size: 12pt; line-height: 120%; }"
    #         io.puts "table { width: 100%; }"
    #         io.puts ".pdf-space-above td {padding-top: 0.2em; }"
    #         io.puts ".pdf-space-below td {padding-bottom: 0.2em; }"
    #         io.puts ".page-break { page-break-after: always; border-top: none; margin-bottom: 0; }"
    #         io.puts "</style>"
    #         io.puts "Test"
    #         io.string
    #     end
    #     c = Curl.post('http://weasyprint:5001/pdf', {:data => pdf}.to_json)
    #     pdf = c.body_str
    #     respond_raw_with_mimetype(pdf, 'application/pdf')
    # end
end
