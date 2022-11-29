class Main < Sinatra::Base
    @@GEN_IMAGE_WIDTHS = [2048, 1200, 1024, 768, 512, 384, 256].sort

    @@BOOTSTRAP_BREAKPOINTS = {
        :lg => 1200,
        :md => 992,
        :sm => 768,
        :xs => 480
    }

    def self.get_website_events
        ts_now = DateTime.now.strftime('%Y-%m-%d')
        $neo4j.neo4j_query(<<~END_OF_QUERY, :today => ts_now).map { |x| x['e'] }
            MATCH (e:WebsiteEvent)
            WHERE e.date_end IS NULL AND e.date < $today
            DELETE e;
        END_OF_QUERY
        $neo4j.neo4j_query(<<~END_OF_QUERY, :today => ts_now).map { |x| x['e'] }
            MATCH (e:WebsiteEvent)
            WHERE e.date_end IS NOT NULL AND e.date_end < $today
            DELETE e;
        END_OF_QUERY
        results = $neo4j.neo4j_query(<<~END_OF_QUERY, :today => ts_now).map { |x| x['e'] }
            MATCH (e:WebsiteEvent)
            RETURN e
            ORDER BY e.date, e.title;
        END_OF_QUERY
        results
    end
    
    post '/api/get_website_events' do
        require_user_who_can_manage_news!
        respond(:events => self.class.get_website_events())
    end
    
    post '/api/delete_website_event' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:id])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id])
            MATCH (e:WebsiteEvent {id: $id})
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
            SET e.id = $id
            SET e.date = $date
            SET e.title = '';
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/change_website_event_date' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:id, :date])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :date => data[:date])
            MATCH (e:WebsiteEvent {id: $id})
            SET e.date = $date;
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/change_website_event_date_end' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:id, :date_end])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :date_end => data[:date_end])
            MATCH (e:WebsiteEvent {id: $id})
            SET e.date_end = $date_end;
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/change_website_event_title' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:id, :title])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :title => data[:title])
            MATCH (e:WebsiteEvent {id: $id})
            SET e.title = $title;
        END_OF_QUERY
        respond(:result => 'yay')
    end

    post '/api/get_news' do
        require_user_who_can_manage_news!
        results = neo4j_query(<<~END_OF_QUERY).map { |x| x }
            MATCH (n:NewsEntry)
            RETURN n.date AS date, n.timestamp AS timestamp, n.title AS title, n.sticky AS sticky, n.published AS published
            ORDER BY n.timestamp DESC;
        END_OF_QUERY
        respond(:news => results)
    end

    post '/api/set_news_published' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:timestamp, :published], :types => {:timestamp => Integer})
        published = data[:published] == 'yes'
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:timestamp => data[:timestamp], :published => published})
            MATCH (n:NewsEntry {timestamp: $timestamp})
            SET n.published = $published
            RETURN n.published AS published;
        END_OF_QUERY
        respond(:published => result['published'])
    end

    post '/api/set_news_sticky' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:timestamp, :sticky], :types => {:timestamp => Integer})
        sticky = data[:sticky] == 'yes'
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:timestamp => data[:timestamp], :sticky => sticky})
            MATCH (n:NewsEntry {timestamp: $timestamp})
            SET n.sticky = $sticky
            RETURN n.sticky AS sticky;
        END_OF_QUERY
        respond(:sticky => result['sticky'])
    end

    post '/api/delete_news_entry' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:timestamp], :types => {:timestamp => Integer})
        result = neo4j_query(<<~END_OF_QUERY, {:timestamp => data[:timestamp]})
            MATCH (n:NewsEntry {timestamp: $timestamp})
            DETACH DELETE n;
        END_OF_QUERY
        respond(:ok => 'yay')
    end

    def _include_file(name, label)
        icon = ''
        if name[-4, 4] == '.pdf'
            icon = "<i class='file-type fa fa-file-pdf-o'></i>"
        elsif name[-4, 4] == '.doc' || name[-5, 5] == '.docx'
            icon = "<i class='file-type fa fa-file-word-o'></i>"
        elsif name[-4, 4] == '.xls' || name[-5, 5] == '.xlsx'
            icon = "<i class='file-type fa fa-file-excel-o'></i>"
        elsif name[-4, 4] == '.ppt' || name[-5, 5] == '.pptx'
            icon = "<i class='file-type fa fa-file-powerpoint-o'></i>"
        elsif name[-4, 4] == '.zip'
            icon = "<i class='file-type fa fa-file-zip-o'></i>"
        end
        "#{icon}<a href='https://#{WEBSITE_HOST}/f/#{name}' target='_blank'>#{label}</a>"
    end
    
    def img_multi_attr_lazy_hash(path, extension, resolutions, lazy = true)
        if resolutions[:cols]
            resolutions[:lg] ||= "#{(@@BOOTSTRAP_BREAKPOINTS[:lg].to_f * resolutions[:cols] / 12).to_i}px"
            resolutions[:md] ||= "#{(@@BOOTSTRAP_BREAKPOINTS[:md].to_f * resolutions[:cols] / 12).to_i}px"
            resolutions[:sm] ||= "#{(@@BOOTSTRAP_BREAKPOINTS[:sm].to_f * resolutions[:cols] / 12).to_i}px"
            resolutions[:xs] ||= "100vw"
        end
        srcset_entries = @@GEN_IMAGE_WIDTHS.map do |w|
            "#{path}-#{w}.#{extension} #{w}w"
        end
        sizes_entries = @@BOOTSTRAP_BREAKPOINTS.map do |key, min_width|
            entry = resolutions[key]
            [:xs, :sm, :md, :lg].each do |k|
                entry ||= resolutions[k]
            end
            entry ||= '100vw'
            "(min-width: #{min_width}px) #{entry}"
        end
        {
            'srcset' => srcset_entries.join(', '),
            'sizes' => sizes_entries.join(', ')
        }
    end
    
    def img_multi_attr_lazy(path, extension, resolutions, lazy = true)
        h = img_multi_attr_lazy_hash(path, extension, resolutions, lazy)
        h.keys.map do |k|
            "#{k}='#{h[k]}'"
        end.join(' ')
    end

    def _include_lazyload_image(slug, options = {})
        dir = ''
        options[:x] ||= 50
        options[:y] ||= 50
        options[:classes] ||= []
        if options[:cols]
            options[:lg] ||= "#{(@@BOOTSTRAP_BREAKPOINTS[:lg].to_f * options[:cols] / 12 / 12 * 9).to_i}px"
            options[:md] ||= "#{(@@BOOTSTRAP_BREAKPOINTS[:md].to_f * options[:cols] / 12 / 12 * 9).to_i}px"
            options[:sm] ||= "#{(@@BOOTSTRAP_BREAKPOINTS[:sm].to_f * options[:cols] / 12 / 12 * 9).to_i}px"
            options[:xs] ||= "100vw"
        end
        StringIO.open do |io|
            io.puts "<picture>"
            ['webp', 'jpg'].each do |extension|
                mime_type = extension == 'webp' ? 'image/webp' : 'image/jpeg'
                io.puts "<source type='#{mime_type}' class='lazy' #{img_multi_attr_lazy(File.join("https://#{WEBSITE_HOST}/gen/i/#{slug}"), extension, options)} />"
            end
            io.puts "<img src='#{slug}-p.jpg' class='#{options[:classes].join(' ')}' style='object-position: #{options[:x]}% #{options[:y]}%' alt='#{options[:label]}' />"
            io.puts "</picture>"
            io.string
        end
    end
    
    def _include_image(slug, mode = nil, caption = nil)
        mode = nil if (mode || '').empty?
        caption = nil if (caption|| '').empty?
        if mode.nil?
            StringIO.open do |io|
                io.puts "<div class='image'>"
#                 io.puts "<img src='https://#{WEBSITE_HOST}/gen/i/#{slug}-1024.jpg' />"
                io.puts _include_lazyload_image(slug)
                io.puts "<div class='caption'>#{caption}</div>" if caption
                io.puts "</div>"
                io.string
            end
        else
            StringIO.open do |io|
                width = mode[1]
                align = mode[0] == 'r' ? 'right' : 'left'
                io.puts "<div class='image iw-#{width} pull-#{align}'>"
#                 io.puts "<img src='https://#{WEBSITE_HOST}/gen/i/#{slug}-1024.jpg' />"
                io.puts _include_lazyload_image(slug, :cols => width.to_i)
                io.puts "<div class='caption'>#{caption}</div>" if caption
                io.puts "</div>"
                io.string
            end
#             "<img src='https://#{WEBSITE_HOST}/gen/i/#{slug}-1024.jpg' class='col-md-4 pull-left' />"
        end
    end
    
    def fix_images(s)
        s.gsub(/image{[^}]+}/) do |x|
            m = x.match(/^image{([^}]+)}$/)
            parts = m[1].split(',')
            slug = parts[0].strip
            pos = (parts[1] || '').strip
            caption = nil
            if ['l3', 'l4', 'l5', 'l6', 'r3', 'r4', 'r5', 'r6'].include?(pos)
                caption = (parts[2, parts.size - 2] || []).join(',').strip
            else
                caption = (parts[1, parts.size - 1] || []).join(',').strip
                pos = nil
            end
            caption = (caption[1, caption.size - 2] || '').strip
            '#{' + "_include_image(\"#{slug}\", \"#{pos}\", \"#{caption.gsub('"', '\\"')}\")}"
        end.gsub(/file{[^}]+}{[^}]+}/) do |x|
            m = x.match(/^file{([^}]+)}{([^}]+)}$/)
            '#{_include_file("' + m[1] + '", "' + m[2] + '")}'
        end
    end

    def eval_lilypads(_content)
        content = _content.dup
        while true
            index = content.index('#{')
            break if index.nil?
            length = 2
            balance = 1
            while index + length < content.size && balance > 0
                c = content[index + length]
                balance -= 1 if c == '}'
                balance += 1 if c == '{'
                length += 1
            end
            code = content[index + 2, length - 3]
            begin
                # STDERR.puts code
                content[index, length] = eval(code).to_s || ''
            rescue
                STDERR.puts "Error while evaluating:"
                STDERR.puts code
                raise
            end
        end
        content
    end

    post '/api/get_news_entry' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:timestamp], :types => {:timestamp => Integer})
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:timestamp => data[:timestamp]})['n']
            MATCH (n:NewsEntry {timestamp: $timestamp})
            RETURN n;
        END_OF_QUERY
        content = result[:content]
        content = fix_images(content)
        content = eval_lilypads(content)
        result[:content_html] = parse_markdown(content)
        respond(result)
    end

    post '/api/get_news_preview' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:markdown], :max_body_length => 64 * 1024,
            :max_string_length => 64 * 1024)
        content = data[:markdown]
        content = fix_images(content)
        content = eval_lilypads(content)
        respond(:html => parse_markdown(content))
    end

    get "/api/website_get_teachers/#{WEBSITE_READ_INFO_SECRET}" do
        data = {}
        data[:teachers] = @@user_info.select do |email, info|
            info[:teacher] && !info[:shorthand].empty? && info[:shorthand][0] != '_'
        end.map do |email, info|
            {:name => info[:display_last_name],
             :email => info[:email]}
        end
        respond(data)
    end
    
    get "/api/website_get_events/#{WEBSITE_READ_INFO_SECRET}" do
        data = {}
        results = neo4j_query(<<~END_OF_QUERY).map { |x| x['e'] }
            MATCH (e:WebsiteEvent)
            RETURN e
            ORDER BY e.date, e.title;
        END_OF_QUERY
        data[:events] = results.map do |x|
            x.select do |k, v|
                [:date, :date_end, :title, :cancelled].include?(k)
            end
        end
        respond(data)
    end
    
    get "/api/get_frontpage_news_entries/#{WEBSITE_READ_INFO_SECRET}" do
        entries = neo4j_query(<<~END_OF_QUERY).map { |x| x['n'] }
            MATCH (n:NewsEntry)
            WHERE n.published = true
            RETURN n
            ORDER BY n.timestamp DESC
            LIMIT 20;
        END_OF_QUERY
        results = []
        entries.each do |entry|
            content = entry[:content]
            content = fix_images(content)
            content = eval_lilypads(content)
            results << {
                :title => entry[:title],
                :timestamp => entry[:timestamp],
                :date => entry[:date],
                :sticky => entry[:sticky],
                :content_html => parse_markdown(content)
            }
        end
        respond(:entries => results)
    end

    get "/api/get_frontpage_news_entries_with_keyword/#{WEBSITE_READ_INFO_SECRET}/:keyword" do
        keyword = params[:keyword].downcase.strip
        entries = neo4j_query(<<~END_OF_QUERY, {:keyword => keyword}).map { |x| x['n'] }
            MATCH (n:NewsEntry)
            WHERE n.published = true AND
            (toLower(n.title) CONTAINS $keyword OR toLower(n.content) CONTAINS $keyword)
            RETURN n
            ORDER BY n.timestamp DESC
            LIMIT 20;
        END_OF_QUERY
        results = []
        entries.each do |entry|
            content = entry[:content]
            content = fix_images(content)
            content = eval_lilypads(content)
            results << {
                :title => entry[:title],
                :timestamp => entry[:timestamp],
                :date => entry[:date],
                :sticky => entry[:sticky],
                :content_html => parse_markdown(content)
            }
        end
        respond(:entries => results)
    end

    post '/api/refresh_news_on_website' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:staging])
        c = Curl.post("#{SCHOOL_WEBSITE_API_URL}/api/update_news_#{(data[:staging] == 'yes') ? 'staging' : 'live'}")
        respond(:yay => 'sure')
    end

    post '/api/refresh_entire_website' do
        require_admin!
        data = parse_request_data(:required_keys => [:staging])
        c = Curl.post("#{SCHOOL_WEBSITE_API_URL}/api/update_all_#{(data[:staging] == 'yes') ? 'staging' : 'live'}")
        respond(:yay => 'sure')
    end

    post '/api/update_news_entry' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:timestamp, :title, :content], 
            :max_body_length => 64 * 1024,
            :max_string_length => 64 * 1024,
            :types => {:timestamp => Integer})
        neo4j_query_expect_one(<<~END_OF_QUERY, {:timestamp => data[:timestamp], :title => data[:title], :content => data[:content]})
            MATCH (n:NewsEntry {timestamp: $timestamp})
            SET n.title = $title
            SET n.content = $content
            RETURN n.timestamp;
        END_OF_QUERY
        respond(:yay => 'sure')
    end

    post '/api/store_news_entry' do
        require_user_who_can_manage_news!
        now = DateTime.now
        data = parse_request_data(:required_keys => [:title, :content], 
            :max_body_length => 64 * 1024,
            :max_string_length => 64 * 1024)
        entry = {
            :timestamp => now.to_time.to_i,
            :date => now.strftime('%Y-%m-%d %H:%M:%S'),
            :title => data[:title],
            :content => data[:content],
            :sticky => false,
            :published => false
        }
        neo4j_query_expect_one(<<~END_OF_QUERY, {:entry => entry, :timestamp => entry[:timestamp]})
            CREATE (n:NewsEntry {timestamp: $timestamp})
            SET n = $entry
            RETURN n.timestamp;
        END_OF_QUERY
        respond(:yay => 'sure')
    end
end
