class Main < Sinatra::Base
    # post '/api/tablet_mac_changed' do
    #     data = parse_request_data(:required_keys => [:code, :access_point_mac])
    #     code = data[:code]
    #     access_point_mac = data[:access_point_mac]
    #     current_datetime = Time.now.strftime('%d.%m.%Y %H:%M:%S')
    #     neo4j_query(<<~END_OF_QUERY, :access_point_mac => access_point_mac, :current_datetime => current_datetime, :code => code)
    #         MERGE (v:SchulTablet {code: $code})
    #         SET v.access_point_mac = $access_point_mac
    #         SET v.last_seen = $current_datetime
    #     END_OF_QUERY
    #     respond(:ok => true)
    # end

    # post '/api/add_mobile_device' do
    #     require_user_who_can_manage_tablets!
    #     data = parse_request_data(:required_keys => [:tablet, :set])
    #     tablet = data[:tablet]
    #     set = data[:set]
    #     code = (0..5).map { |x| rand(10).to_s }.join('')
    #     neo4j_query(<<~END_OF_QUERY, :tablet => tablet, :set => set, :code => code)
    #         MERGE (v:SchulTablet {code: $code})
    #         SET v.set = $set
    #         SET v.tablet = $tablet
    #         RETURN v.code;
    #     END_OF_QUERY
    #     respond(:code => code)
    # end

    # post '/api/remove_mobile_device' do
    #     require_user_who_can_manage_tablets!
    #     data = parse_request_data(:required_keys => [:code])
    #     code = data[:code]
    #     neo4j_query(<<~END_OF_QUERY, :code => code)
    #         MATCH (v:SchulTablet {code: $code})
    #         DELETE v
    #     END_OF_QUERY
    #     respond(:ok => true)
    # end

    def print_tablet_locations
        require_user_who_can_manage_tablets!
        tablets = []
        @@tablet_sets.select {|key, tablet_set| tablet_set[:is_tablet_set]}.each do |key, tablet_set|
            (1..tablet_set[:count])&.each do |name|
                tablets.append "#{tablet_set[:prefix].to_i}.#{name}"
            end
            tablet_set[:includes]&.each do |name|
                tablets.append "#{tablet_set[:prefix].to_i}.#{name}"
            end
            tablet_set[:includes_not]&.each do |name|
                tablets.delete "#{tablet_set[:prefix].to_i}.#{name}"
            end
        end
        StringIO.open do |io|
            io.puts "<table class='table narrow table-striped' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr><th>Tablet</th><th>Access Point</th><th>Zuletzt gesehen</th></tr>"
            io.puts "</thead><tbody>"
            for tablet in tablets do
                io.puts "<tr><td>#{tablet}</td><td></td><td></td></tr>"
            end
            io.puts "</tbody></table>"
            io.string
        end
    end
end