class Main < Sinatra::Base
    def css_for_font(font)
        if font == 'Alegreya'
            {'font-family' => 'AlegreyaSans', 'letter-spacing' => 'unset'}
        elsif font == 'Billy'
            {'font-family' => 'Billy', 'letter-spacing' => 'unset'}
        elsif font == 'Riffic'
            {'font-family' => 'Riffic', 'letter-spacing' => '0.05em'}
        else
            {'font-family' => 'Roboto', 'letter-spacing' => 'unset'}
        end
    end
    
    post '/api/set_font' do
        require_user!
        data = parse_request_data(:required_keys => [:font])
        assert(AVAILABLE_FONTS.include?(data[:font]))
        results = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :font => data[:font])
            MATCH (u:User {email: {email}})
            SET u.font = {font};
        END_OF_QUERY
        respond(:ok => true, :css => css_for_font(data[:font]))
    end
    
    post '/api/set_color_scheme' do
        require_user!
        data = parse_request_data(:required_keys => [:scheme])
        data[:scheme].downcase!
        assert('ld'.include?(data[:scheme][0]))
        assert(data[:scheme][1, 18] =~ /^[0-9a-f]{18}[0-8]?$/)
        primary_color = '#' + data[:scheme][7, 6]
        results = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :scheme => data[:scheme])
            MATCH (u:User {email: {email}})
            SET u.color_scheme = {scheme};
        END_OF_QUERY
        @@renderer.render(["##{data[:scheme][1, 6]}", "##{data[:scheme][7, 6]}", "##{data[:scheme][13, 6]}", '(no title)'], @session_user[:email])
        respond(:ok => true, :primary_color_darker => darken("##{data[:scheme][7, 6]}", 0.8), :darker => rgb_to_hex(mix(hex_to_rgb(primary_color), [0, 0, 0], 0.6)))
    end
    
    def get_gradients()
        results = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User) 
            WITH COALESCE(u.color_scheme, '#{@@standard_color_scheme}') AS scheme
            RETURN  scheme, count(scheme) AS count ORDER BY count DESC, scheme DESC;
        END_OF_QUERY
        histogram = {}
        results.each do |entry|
            entry['scheme'] ||= @@standard_color_scheme
            histogram[entry['scheme'][1, 18]] ||= 0
            histogram[entry['scheme'][1, 18]] += entry['count']
        end
        histogram_style = {}
        results.each do |entry|
            entry['scheme'] ||= @@standard_color_scheme
            style = (entry['scheme'][19] || '0').to_i
            histogram_style[style] ||= 0
            histogram_style[style] += entry['count']
        end
        color_schemes = @@color_scheme_colors.map do |x|
            paint_colors = x[0, 3].map do |c|
                rgb_to_hex(mix(hex_to_rgb(c), [255, 255, 255], 0.3))
            end
            [x[1], x[0, 3], paint_colors, x[3], x[4], x[5], histogram[x[0, 3].join('').gsub('#', '')], color_palette_for_color_scheme("l#{x[0, 3].join('').gsub('#', '')}")]
        end
        {:color_schemes => color_schemes,
         :style_histogram => histogram_style}
    end
end
