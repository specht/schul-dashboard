class Main < Sinatra::Base
    post '/api/get_website_events' do
        require_user_who_can_manage_news!
        ts_now = DateTime.now.strftime('%Y-%m-%d')
        neo4j_query(<<~END_OF_QUERY, :today => ts_now).map { |x| x['e'].props }
            MATCH (e:WebsiteEvent)
            WHERE e.date < {today}
            DELETE e;
        END_OF_QUERY
        results = neo4j_query(<<~END_OF_QUERY, :today => ts_now).map { |x| x['e'].props }
            MATCH (e:WebsiteEvent)
            RETURN e
            ORDER BY e.date, e.title;
        END_OF_QUERY
        respond(:events => results)
    end
    
    post '/api/delete_website_event' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:id])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id])
            MATCH (e:WebsiteEvent {id: {id}})
            DELETE e;
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/create_website_event' do
        require_user_who_can_manage_news!
        id = RandomTag.generate()
        ts_now = DateTime.now.strftime('%Y-%m-%d')
        neo4j_query(<<~END_OF_QUERY, :id => id, :date => ts_now)
            CREATE (e:WebsiteEvent)
            SET e.id = {id}
            SET e.date = {date}
            SET e.title = '';
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/change_website_event_date' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:id, :date])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :date => data[:date])
            MATCH (e:WebsiteEvent {id: {id}})
            SET e.date = {date};
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/change_website_event_title' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:id, :title])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :title => data[:title])
            MATCH (e:WebsiteEvent {id: {id}})
            SET e.title = {title};
        END_OF_QUERY
        respond(:result => 'yay')
    end
end
