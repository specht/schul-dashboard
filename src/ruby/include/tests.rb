class Main < Sinatra::Base
    post '/api/get_tests' do
        require_teacher!
        data = parse_request_data(:required_keys => [:start_date])
        start_date = data[:start_date]
        end_date = (Date.parse(start_date) + 60).strftime('%Y-%m-%d')
        tests = neo4j_query(<<~END_OF_QUERY, :start_date => start_date, :end_date => end_date)
            MATCH (t:Test)-[:BELONGS_TO]->(u:User)
            WHERE t.date >= {start_date} AND t.date <= {end_date}
            RETURN t, u;
        END_OF_QUERY
        events = []
        @@ferien_feiertage.each do |event|
            events << {
                :start => event[:from],
                :end => event[:to],
                :title => event[:title]
            }
        end
        respond(:events => events)
    end
end
