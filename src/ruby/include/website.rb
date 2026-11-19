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

    # Without a year: all entries, as always (the page of today's design).
    # Neues Design: {year: 2026} gives that calendar year's entries and the
    # years there are (with their counts) – read-only, same permission.
    post '/api/get_news' do
        require_user_who_can_manage_news!
        request.body.rewind
        body = request.body.read(512).to_s
        request.body.rewind
        parsed = (JSON.parse(body) rescue nil)
        wants_year = parsed.is_a?(Hash) && parsed.include?('year')
        if wants_year
            data = parse_request_data(:required_keys => [:year], :types => {:year => Integer})
            year = data[:year]
            assert(year >= 2000 && year <= 2100)
            # NewsEntry/timestamp is unique, so the range uses its index
            results = neo4j_query(<<~END_OF_QUERY, :from => Time.new(year, 1, 1).to_i, :to => Time.new(year + 1, 1, 1).to_i).map { |x| x }
                MATCH (n:NewsEntry)
                WHERE n.timestamp >= $from AND n.timestamp < $to
                RETURN n.date AS date, n.timestamp AS timestamp, n.title AS title, n.sticky AS sticky, n.published AS published
                ORDER BY n.timestamp DESC;
            END_OF_QUERY
            counts = Hash.new(0)
            neo4j_query(<<~END_OF_QUERY).each { |x| counts[Time.at(x['timestamp']).year] += 1 }
                MATCH (n:NewsEntry)
                WHERE n.timestamp IS NOT NULL
                RETURN n.timestamp AS timestamp;
            END_OF_QUERY
            years = counts.keys.sort.reverse.map { |y| {:year => y, :count => counts[y]} }
            respond(:news => results, :year => year, :years => years)
        else
            results = neo4j_query(<<~END_OF_QUERY).map { |x| x }
                MATCH (n:NewsEntry)
                RETURN n.date AS date, n.timestamp AS timestamp, n.title AS title, n.sticky AS sticky, n.published AS published
                ORDER BY n.timestamp DESC;
            END_OF_QUERY
            respond(:news => results)
        end
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
    
    # The website (gyst-website) styles this HTML with its own CSS: keep the
    # classes that are there (image, iw-N, pull-left/right, caption) and
    # only add new ones. image-full: an image without position (full
    # width); image-float: an image beside the text. crop: [x, y] in
    # percent, where the image sits when it is cropped (pos=x,y; data-pos on
    # .image, object-position on the img).
    def _include_image(slug, mode = nil, caption = nil, crop = nil)
        mode = nil if (mode || '').empty?
        caption = nil if (caption|| '').empty?
        crop_attr = crop ? " data-pos='#{crop[0]} #{crop[1]}'" : ''
        crop_options = crop ? {:x => crop[0], :y => crop[1]} : {}
        if mode.nil?
            StringIO.open do |io|
                io.puts "<div class='image image-full'#{crop_attr}>"
#                 io.puts "<img src='https://#{WEBSITE_HOST}/gen/i/#{slug}-1024.jpg' />"
                io.puts _include_lazyload_image(slug, crop_options)
                io.puts "<div class='caption'>#{caption}</div>" if caption
                io.puts "</div>"
                io.string
            end
        else
            StringIO.open do |io|
                width = mode[1]
                align = mode[0] == 'r' ? 'right' : 'left'
                io.puts "<div class='image image-float iw-#{width} pull-#{align}'#{crop_attr}>"
#                 io.puts "<img src='https://#{WEBSITE_HOST}/gen/i/#{slug}-1024.jpg' />"
                io.puts _include_lazyload_image(slug, crop_options.merge(:cols => width.to_i))
                io.puts "<div class='caption'>#{caption}</div>" if caption
                io.puts "</div>"
                io.string
            end
#             "<img src='https://#{WEBSITE_HOST}/gen/i/#{slug}-1024.jpg' class='col-md-4 pull-left' />"
        end
    end
    
    # The public website's address of a news entry (the website's article
    # page, beitrag-<timestamp in base 36>); nil without SCHOOL_WEBSITE_URL
    # and until the website serves these pages (WEBSITE_ARTICLE_LINKS).
    def self.news_public_url_base
        return nil unless defined?(WEBSITE_ARTICLE_LINKS) && WEBSITE_ARTICLE_LINKS == true
        base = defined?(SCHOOL_WEBSITE_URL) ? SCHOOL_WEBSITE_URL.to_s.strip.sub(/\/+\z/, '') : ''
        base.empty? ? nil : base
    end

    def self.news_public_url(timestamp, base = news_public_url_base)
        base && "#{base.sub(/\/+\z/, '')}/beitrag-#{timestamp.to_i.to_s(36)}"
    end

    # Neues Design: the news editor as building blocks (preview/news.js) and
    # the base of the public links, only for those who see the new design
    def news_editor_preview_script
        return '' unless ui_preview?
        "\n<script>var pv_news_public_base = #{self.class.news_public_url_base.to_json};</script>" +
        "\n<script src='#{preview_asset('/preview/news.js')}'></script>"
    end

    NEWS_GALLERY_MAX_IMAGES = 12
    # Several photos as a grid with one caption below (gallery{a, b, c, "Fotos: …"}).
    # A wrapper of its own (not .image, so the website doesn't take the whole
    # gallery for one image), laid out by the website's CSS; without that the
    # photos stand one below the other. gallery-N gives the number of photos,
    # so the CSS can pick the columns.
    def _include_gallery(slugs, caption = nil)
        caption = nil if (caption || '').empty?
        cols = [2, 4].include?(slugs.size) ? 6 : (slugs.size == 1 ? 12 : 4)
        StringIO.open do |io|
            io.puts "<div class='image-gallery gallery-#{slugs.size}'>"
            io.puts "<div class='gallery-items'>"
            slugs.each do |slug|
                io.puts "<div class='gallery-item'>"
                io.puts _include_lazyload_image(slug, :cols => cols)
                io.puts "</div>"
            end
            io.puts "</div>"
            io.puts "<div class='caption'>#{caption}</div>" if caption
            io.puts "</div>"
            io.string
        end
    end

    NEWS_IMAGE_POSITIONS = %w(l3 l4 l5 l6 r3 r4 r5 r6)
    NEWS_ROW_RATIOS = %w(3:2 4:3 1:1 16:9)
    NEWS_SLUG = /\A[a-zA-Z0-9\-_]+\z/

    # The inside of image{…}: slug, an optional position (l3–l6, r3–r6), an
    # optional pos=x,y (where the image sits in a cropped frame, percent
    # from left and top as in object-position; before the caption) and the
    # caption in quotes. Returns [slug, pos, caption, crop].
    def parse_news_image(body)
        quote = body.index('"')
        head = quote ? body[0, quote] : body
        tail = quote ? body[quote..-1] : ''
        crop = nil
        m = head.match(/,\s*pos=(\d{1,3}),(\d{1,3})\s*(,|\z)/)
        if m
            crop = [m[1].to_i.clamp(0, 100), m[2].to_i.clamp(0, 100)]
            head = head.sub(m[0], m[3] == ',' ? ',' : '')
        end
        parts = (head + tail).split(',')
        slug = parts[0].to_s.strip
        pos = (parts[1] || '').strip
        if NEWS_IMAGE_POSITIONS.include?(pos)
            caption = (parts[2, parts.size - 2] || []).join(',').strip
        else
            caption = (parts[1, parts.size - 1] || []).join(',').strip
            pos = nil
        end
        caption = (caption[1, caption.size - 2] || '').strip
        [slug, pos, caption, crop]
    end

    # Two or three images side by side, all cropped to one ratio
    # (images{3:2, "shared caption"}{image{…} image{…}}): .image elements in
    # a wrapper of their own; each keeps its caption and its position.
    def _include_image_row(ratio, images, caption = nil)
        caption = nil if (caption || '').empty?
        cols = images.size == 2 ? 6 : 4
        StringIO.open do |io|
            io.puts "<div class='image-row ratio-#{ratio.tr(':', '-')} images-#{images.size}'>"
            images.each do |slug, image_caption, crop|
                crop ||= [50, 50]
                io.puts "<div class='image image-in-row' data-pos='#{crop[0]} #{crop[1]}'>"
                io.puts _include_lazyload_image(slug, :cols => cols, :x => crop[0], :y => crop[1])
                io.puts "<div class='caption'>#{image_caption}</div>" unless (image_caption || '').empty?
                io.puts "</div>"
            end
            io.puts "<div class='caption image-row-caption'>#{caption}</div>" if caption
            io.puts "</div>"
            io.string
        end
    end

    NEWS_IMAGE_ROW = /images\{\s*([0-9]+:[0-9]+)\s*(?:,\s*"([^"{}]*)")?\s*\}\{((?:\s*image\{[^{}]*\}\s*)+)\}/

    # images{…}{…}, image{slug, [l3–r6,] [pos=x,y,] "caption"},
    # gallery{slug, slug, …, "caption"} and file{...}{...} in news texts
    # become HTML by calling the helpers directly – the text itself is never
    # evaluated as Ruby.
    def render_news_includes(s)
        s.gsub(NEWS_IMAGE_ROW) do |x|
            ratio, caption, inner = $1, $2, $3
            images = inner.scan(/image\{([^{}]*)\}/).map { |m| parse_news_image(m[0]) }
            if NEWS_ROW_RATIOS.include?(ratio) && [2, 3].include?(images.size) && images.all? { |i| i[0] =~ NEWS_SLUG }
                _include_image_row(ratio, images.map { |slug, _pos, image_caption, crop| [slug, image_caption, crop] }, caption)
            else
                x
            end
        end.gsub(/image{[^}]+}/) do |x|
            m = x.match(/^image{([^}]+)}$/)
            slug, pos, caption, crop = parse_news_image(m[1])
            _include_image(slug, pos, caption, crop)
        end.gsub(/gallery{[^}]+}/) do |x|
            m = x.match(/^gallery{([^}]+)}$/)
            body = m[1]
            caption = nil
            quote = body.index('"')
            if quote
                caption = body[quote..-1].strip
                caption = (caption[1, caption.size - 2] || '').strip
                body = body[0, quote]
            end
            slugs = body.split(',').map { |part| part.strip }.reject { |part| part.empty? }
            if slugs.empty? || slugs.size > NEWS_GALLERY_MAX_IMAGES || slugs.any? { |slug| slug !~ /\A[a-zA-Z0-9\-_]+\z/ }
                x
            else
                _include_gallery(slugs, caption)
            end
        end.gsub(/file{[^}]+}{[^}]+}/) do |x|
            m = x.match(/^file{([^}]+)}{([^}]+)}$/)
            _include_file(m[1], m[2])
        end
    end

    post '/api/get_news_entry' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:timestamp], :types => {:timestamp => Integer})
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:timestamp => data[:timestamp]})['n']
            MATCH (n:NewsEntry {timestamp: $timestamp})
            RETURN n;
        END_OF_QUERY
        content = result[:content]
        content = render_news_includes(content)
        result[:content_html] = parse_markdown(content)
        respond(result)
    end

    post '/api/get_news_preview' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:markdown], :max_body_length => 64 * 1024,
            :max_string_length => 64 * 1024)
        content = data[:markdown]
        content = render_news_includes(content)
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
    
    # The website's news, newest first. Without parameters the latest 20, as
    # before; with offset and limit (1..100) one page of them, and the number
    # of all published entries (total) – the website pages through them.
    get "/api/get_frontpage_news_entries/#{WEBSITE_READ_INFO_SECRET}" do
        offset_s = params[:offset].to_s
        limit_s = params[:limit].to_s
        offset = offset_s =~ /\A\d{1,7}\z/ ? offset_s.to_i : 0
        limit = limit_s =~ /\A\d{1,4}\z/ ? limit_s.to_i : 20
        limit = [[limit, 1].max, 100].min
        entries = neo4j_query(<<~END_OF_QUERY, {:offset => offset, :limit => limit}).map { |x| x['n'] }
            MATCH (n:NewsEntry)
            WHERE n.published = true
            RETURN n
            ORDER BY n.timestamp DESC
            SKIP $offset
            LIMIT $limit;
        END_OF_QUERY
        total = neo4j_query_expect_one(<<~END_OF_QUERY)['total']
            MATCH (n:NewsEntry)
            WHERE n.published = true
            RETURN count(n) AS total;
        END_OF_QUERY
        results = []
        entries.each do |entry|
            content = entry[:content]
            content = render_news_includes(content)
            results << {
                :title => entry[:title],
                :timestamp => entry[:timestamp],
                :date => entry[:date],
                :sticky => entry[:sticky],
                :content_html => parse_markdown(content)
            }
        end
        respond(:entries => results, :total => total.to_i)
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
            content = render_news_includes(content)
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
