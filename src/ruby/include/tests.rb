class Main < Sinatra::Base
    post '/api/get_tests' do
        require_teacher!
        data = parse_request_data(:required_keys => [:start_date, :klasse])
        start_date = data[:start_date]
        end_date = (Date.parse(start_date) + 60).strftime('%Y-%m-%d')
        klasse = data[:klasse]
        events = []
        @@ferien_feiertage.each do |event|
            events << {
                :start => event[:from],
                :end => (Date.parse(event[:to]) + 1).strftime('%Y-%m-%d'),
                :title => event[:title],
                :extendedProps => {
                    :type => :holiday
                }
            }
        end
        switch_week_entries = []
        p = Date.parse(start_date)
        pend = Date.parse(end_date)
        while p <= pend && p <= Date.parse(@@config[:last_day])
            sw = Main.get_switch_week_for_date(p)
            if switch_week_entries.empty? || switch_week_entries.last[:sw] != sw
                title = "#{sw}-Woche"
                switch_week_entries << {:sw => sw, :start => p.strftime('%Y-%m-%d'), :end => p.strftime('%Y-%m-%d'), :title => title}
            else
                switch_week_entries.last[:end] = p.strftime('%Y-%m-%d')
            end
            p += 1
        end
        switch_week_entries.each do |entry|
            if entry[:sw]
                events << {
                    :start => entry[:start],
                    :end => (Date.parse(entry[:end]) + 1).strftime('%Y-%m-%d'),
                    :title => entry[:title],
                    :extendedProps => {
                        :type => :switch_week
                    }
                }
            end
        end
        tests = neo4j_query(<<~END_OF_QUERY, :start_date => start_date, :end_date => end_date, :klasse => klasse).map { |x| {:user => x['u'].props, :test => x['t'].props } }
            MATCH (t:Test {klasse: {klasse}})-[:ORGANIZED_BY]->(u:User)
            WHERE t.datum >= {start_date} AND t.datum <= {end_date}
            RETURN t, u;
        END_OF_QUERY
        tests.each do |event|
            user_info = @@user_info[event[:user][:email]]
            title = "#{event[:test][:typ]} #{event[:test][:fach]} (#{@@user_info[event[:user][:email]][:shorthand]})"
            unless (event[:test][:kommentar] || '').strip.empty?
                title += " – #{event[:test][:kommentar]}"
            end
            events << {
                :start => event[:test][:datum],
                :end => event[:test][:datum],
                :title => title,
                :extendedProps => {
                    :type => :test,
                    :test => event[:test],
                    :display_name => user_info[:display_name],
                    :shorthand => user_info[:shorthand],
                    :is_session_user => event[:user][:email] == @session_user[:email]
                }
            }
        end
        respond(:events => events)
    end
    
    post '/api/save_test' do
        require_teacher!
        data = parse_request_data(:required_keys => [:klasse, :datum, :fach, :kommentar, :typ])
        id = RandomTag.generate(12)
        timestamp = Time.now.to_i
        test = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :klasse => data[:klasse], :datum => data[:datum], :fach => data[:fach], :kommentar => data[:kommentar], :typ => data[:typ])['t'].props
            MATCH (a:User {email: {session_email}})
            CREATE (t:Test {id: {id}, klasse: {klasse}, datum: {datum}, fach: {fach}, kommentar: {kommentar}, typ: {typ}})
            SET t.created = {timestamp}
            SET t.updated = {timestamp}
            CREATE (t)-[:ORGANIZED_BY]->(a)
            RETURN t;
        END_OF_QUERY
        result = {
            :tid => test[:id], 
            :test => test
        }
        respond(:ok => true, :test => result)
    end

    post '/api/update_test' do
        require_teacher!
        data = parse_request_data(:required_keys => [:klasse, :datum, :fach, :kommentar, :typ, :id])
        timestamp = Time.now.to_i
        test = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => data[:id], :klasse => data[:klasse], :datum => data[:datum], :fach => data[:fach], :kommentar => data[:kommentar], :typ => data[:typ])['t'].props
            MATCH (t:Test {id: {id}})-[:ORGANIZED_BY]->(a:User {email: {session_email}})
            SET t.updated = {timestamp}
            SET t.klasse = {klasse}
            SET t.datum = {datum}
            SET t.fach = {fach}
            SET t.kommentar = {kommentar}
            SET t.typ = {typ}
            RETURN t;
        END_OF_QUERY
        result = {
            :tid => test[:id], 
            :test => test
        }
        respond(:ok => true, :test => result)
    end

    post '/api/delete_test' do
        require_teacher!
        data = parse_request_data(:required_keys => [:id])
        neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :id => data[:id])
            MATCH (t:Test {id: {id}})-[:ORGANIZED_BY]->(a:User {email: {session_email}})
            DETACH DELETE t;
        END_OF_QUERY
        respond(:ok => true)
    end
end
