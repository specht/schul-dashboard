require 'chunky_png'
# require 'rmagick'
# include Magick


class Main < Sinatra::Base
    MAX_CYPHER_LEVEL = 10

    #  1. Caesar
    #  2. Skytale
    #  9. Superimpose two images
    #  5. Anaglyph
    #  4. Autostereogram
    # 10. Aztec Code https://github.com/delimitry/aztec_code_generator
    #  3. Audio spectrum (libfftw?)
    #  6. Image metadata
    #  7. Image steganography (palette / LSB)
    #  8. GameBoy ROM cartridge https://laroldsjubilantjunkyard.com/tutorials/how-to-make-a-gameboy-game/minimal-gbdk-project/
    
    CYPHER_LANGUAGES = %w(ada algol awk bash basic c cobol dbase delphi erlang fortran
        go haskell java lisp logo lua masm modula oberon pascal perl php postscript
        prolog ruby rust scala scumm smalltalk squeak swift tex zpl)

    def caesar(s, shift)
        t = ''
        s.each_char do |c|
            code = c.upcase.ord
            if code >= 'A'.ord && code <= 'Z'.ord
                i = code - 'A'.ord
                i = (i + shift) % 26
                c = (i + 'A'.ord).chr
            end
            t += c
        end
        t
    end

    def skytale(s, w)
        s = s.upcase.gsub(' ', '')
        t = ''
        (0...w).each do |x|
            i = x
            while i < s.size
                t += s[i]
                i += w
            end
        end
        t
    end

    def get_next_cypher_password
        @cypher_next_password = nil
        srand(@cypher_seed)
        if @cypher_level == 0
            languages = CYPHER_LANGUAGES.shuffle
            lang = languages[@cypher_level]
            line = [
                "Das naechste Loesungswort lautet #{lang}",
                "Das Passwort lautet #{lang}",
                "Versuch es mal mit #{lang}",
                "Wenn du #{lang} eingibst dann sollte es klappen",
                "#{lang} ist das naechste Passwort"
            ].sample
            @cypher_next_password = lang
            @cypher_token = caesar(line, (rand * 25).floor + 1)
        elsif @cypher_level == 1
            languages = CYPHER_LANGUAGES.shuffle
            lang = languages[@cypher_level]
            line = [
                "Das naechste Loesungswort lautet #{lang}",
                "Das Passwort lautet #{lang}",
                "Versuch es mal mit #{lang}",
                "Wenn du #{lang} eingibst dann sollte es klappen",
                "#{lang} ist das naechste Passwort"
            ].sample
            @cypher_next_password = lang
            @cypher_token = skytale(line, [3, 4, 5, 6].sample)
        end
    end

    def cypher_content
        require_user!
        parts = request.env['REQUEST_PATH'].split('/')
        provided_password = (parts[2] || '').strip.downcase
        provided_password = nil if provided_password.empty?
        debug "provided: [#{provided_password}]"
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.cypher_level, 0) AS cypher_level,
            u.cypher_seed AS cypher_seed,
            COALESCE(u.failed_cypher_tries, 0) AS failed_cypher_tries,
            COALESCE(u.cypher_name, '') AS cypher_name;
        END_OF_QUERY
        @cypher_level = result['cypher_level']
        @cypher_seed = result['cypher_seed']
        @cypher_name = result['cypher_name'].strip
        failed_cypher_tries = result['failed_cypher_tries']
        tries_left = 3 - failed_cypher_tries
        if @cypher_seed.nil? || (@cypher_level == 0 && provided_password.nil?)
            @cypher_seed = Time.now.to_i
            result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :cypher_seed => @cypher_seed})
                MATCH (u:User {email: $email})
                SET u.cypher_seed = $cypher_seed;
            END_OF_QUERY
        end

        get_next_cypher_password()

        STDERR.puts "CYPHER // #{@session_user[:email]} // level: #{@cypher_level}, next password: #{@cypher_next_password}#{@cypher_next_password.nil? ? '(nil)':''}"

        unless provided_password.nil? || @cypher_next_password.nil?
            if provided_password == @cypher_next_password
                @cypher_level += 1
                result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :cypher_level => @cypher_level})
                    MATCH (u:User {email: $email})
                    SET u.cypher_level = $cypher_level,
                    u.failed_cypher_tries = 0;
                END_OF_QUERY
            else
                result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
                    MATCH (u:User {email: $email})
                    SET u.failed_cypher_tries = COALESCE(u.failed_cypher_tries, 0) + 1;
                END_OF_QUERY
                if tries_left <= 1
                    result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
                        MATCH (u:User {email: $email})
                        SET u.cypher_level = 0, u.failed_cypher_tries = 0, u.cypher_name = '';
                    END_OF_QUERY
                end
            end
        end
        unless provided_password.nil?
            redirect "#{WEB_ROOT}/cyph3r", 302
        end

        get_next_cypher_password()

        StringIO.open do |io|
            # io.puts "<p style='text-align: left; margin-top: 0;'><b>#{@session_user[:first_name]}</b> &lt;#{@session_user[:email]}&gt;</p>"
            if @cypher_level == MAX_CYPHER_LEVEL
                # io.puts "<p style='float: right; margin-top: 0;'><a href='/hackers'>=&gt; Hall of Fame</a></p>"
                io.puts File.read('/static/cypher/hall_of_fame.html')
                result = neo4j_query(<<~END_OF_QUERY)
                    MATCH (u:User)
                    WHERE COALESCE(u.cypher_level, 0) > 0
                    RETURN u.email, u.cypher_level, COALESCE(u.cypher_name, '') AS cypher_name
                END_OF_QUERY
                io.puts "<p>"
                io.puts "Bisher #{result.size == 1 ? 'hat' : 'haben'} <b>#{result.size} Code Cracker:in#{result.size == 1 ? '' : 'nen'}</b> versucht, die Aufgaben zu lösen."
                histogram = {}
                names = []
                result.each do |row|
                    histogram[row['u.cypher_level']] ||= []
                    histogram[row['u.cypher_level']] << row['u.email']
                    names << row['cypher_name'] unless row['cypher_name'].strip.empty?
                end
                names.sort!
                parts = []
                histogram.keys.sort.each do |level|
                    l = 'in der <b>Hall of Fame</b>'
                    if level + 1 <= MAX_CYPHER_LEVEL
                        l = "in <b>Level #{level + 1}</b>"
                    end
                    parts << "<b>#{histogram[level].size} Person#{histogram[level].size == 1 ? '' : 'en'}</b> #{l}"
                end
                io.puts "Davon befinde#{histogram[histogram.keys.sort.first].size == 1 ? 't' : 'n'} sich #{join_with_sep(parts, ', ', ' und ')}."
                io.puts "</p>"
                io.puts "<hr style='margin-bottom: 15px;'/>"
                # io.puts "<p>"
                # io.puts "Hier kannst du festlegen, ob und wie du in der Hall of Fame erscheinen möchtest:"
                # io.puts "</p>"
                # io.puts "<hr />"
                possible_names = []
                possible_names << @session_user[:first_name]
                unless @session_user[:teacher]
                    possible_names << "#{@session_user[:first_name]} (#{@session_user[:klasse]})"
                end
                possible_names << @session_user[:display_name]
                unless @session_user[:teacher]
                    possible_names << "#{@session_user[:display_name]} (#{@session_user[:klasse]})"
                else
                    possible_names << "#{@session_user[:display_last_name]}"
                end

                io.puts "<p style='text-align: left; margin-top: 0;'>"
                io.puts "<span class='name-pref' data-name=''>[#{@cypher_name == '' ? 'x': ' '}] Ich möchte <b>nicht</b> aufgelistet werden.</span><br />"
                possible_names.each do |name|
                    io.puts "<span class='name-pref' data-name=\"#{name}\">[#{@cypher_name == name ? 'x': ' '}] Ich möchte als <b>»#{name}«</b> erscheinen.</span><br />"
                end
                io.puts "<span class='cypher-reset text-danger'>[!] Ich möchte meinen <b>Fortschritt löschen</b> und von vorn beginnen.</span>"
                io.puts "<span class='text-danger' id='cypher_reset_confirm' style='display: none;'><br />&nbsp;&nbsp;&nbsp;&nbsp;Bist du sicher? <span id='cypher_reset_confirm_yes'><b>[Ja]</b></span> <span id='cypher_reset_confirm_no'><b>[Nein]</b></span></span>"
                io.puts "</p>"
                io.puts "<h2><b>Hall of Fame</b></h2>"
                names.each do |name|
                    io.puts "<p class='name'>#{name}</p>"
                end
                io.puts File.read('/static/cypher/hall_of_fame_foot.html')
            else
                io.puts File.read('/static/cypher/title.html').gsub('#{next_cypher_level}', (@cypher_level + 1).to_s)
                if failed_cypher_tries == 0
                    if @cypher_level > 0
                        io.puts "<p><b>Gut gemacht!</b></p>"
                        io.puts "<hr />"
                    end
                else
                    if @cypher_level > 0
                        tries_left = 3 - failed_cypher_tries
                        io.puts "<p class='text-danger'><b>Achtung!</b> Deine letzte Antwort war leider falsch. Du hast noch <b>#{tries_left} Versuch#{tries_left == 1 ? '' : 'e'}</b>, bevor du wieder von vorn beginnen musst.</p>"
                        io.puts "<hr />"
                    else
                        io.puts "<p class='text-danger'><b>Achtung!</b> Deine letzte Antwort war leider falsch.</p>"
                        io.puts "<hr />"
                    end
                end
                path = "/static/cypher/level_#{@cypher_level + 1}.html"
                if File.exists?(path)
                    io.puts File.read(path)
                end
                io.puts File.read('/static/cypher/form.html')
            end
            io.string
        end
    end

    post '/api/cypher_set_name' do
        require_user!
        data = parse_request_data(:required_keys => [:name], :max_body_length => 2048, :max_string_length => 2048)
        neo4j_query("MATCH (u:User {email: $email}) SET u.cypher_name = $name;", {:email => @session_user[:email], :name => data[:name]})
        display_name = @session_user[:display_name]
        deliver_mail(data[:name]) do
            to WEBSITE_MAINTAINER_EMAIL
            bcc SMTP_FROM
            from SMTP_FROM

            subject "CYPH3R: #{display_name}"
        end
        respond(:alright => 'yeah')
    end

    post '/api/cypher_reset' do
        require_user!
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            SET u.cypher_level = 0, u.failed_cypher_tries = 0, u.cypher_name = '';
        END_OF_QUERY
        respond(:alright => 'yeah')
    end

    def load_font(path)
        STDERR.puts "Loading font fron #{path}..."
        font = {}
        File.open(path) do |f|
            char = nil
            f.each_line do |line|
                if line[0, 9] == 'STARTCHAR'
                    char = {}
                elsif line[0, 8] == 'ENCODING'
                    char[:encoding] = line.sub('ENCODING ', '').strip.to_i
                elsif line[0, 7] == 'ENDCHAR'
                    font[char[:encoding]] = char
                    char = nil
                elsif line[0, 3] == 'BBX'
                    parts = line.split(' ')
                    char[:width] = parts[1].to_i
                    char[:height] = parts[2].to_i
                elsif line[0, 6] == 'BITMAP'
                    char[:bitmap] = []
                else
                    if char && char[:bitmap]
                        char[:bitmap] << line.to_i(16)
                    end
                end
            end
        end
        font
    end

    def draw_text(png, s, font, color, options = {})
        @@cypher_fonts ||= {}
        @@cypher_fonts[font] ||= load_font("fonts/ucs/#{font}.bdf")
        options[:x] ||= 0
        options[:y] ||= 0
        options[:scale] ||= 1
        dx = 0
        s.each_char do |c|
            glyph = @@cypher_fonts[font][c.ord]
            if glyph
                w = ((((glyph[:width] - 1) >> 3) + 1) << 3) - 1
                (0...glyph[:height]).each do |iy|
                    (0...glyph[:width]).each do |ix|
                        if (((glyph[:bitmap][iy] >> (w - ix)) & 1) == 1)
                            (0...options[:scale]).each do |oy|
                                (0...options[:scale]).each do |ox|
                                    png.set_pixel_if_within_bounds(options[:x] + (ix + dx) * options[:scale] + ox, options[:y] + iy * options[:scale] + oy, color)
                                end
                            end
                        end
                    end
                end
                dx += glyph[:width]
            end
        end
    end

    def text_width(s, font, options = {})
        @@cypher_fonts ||= {}
        @@cypher_fonts[font] ||= load_font("fonts/ucs/#{font}.bdf")
        width = 0
        s.each_char do |c|
            glyph = @@cypher_fonts[font][c.ord]
            if glyph
                width += glyph[:width]
            end
        end
        width
    end

    get '/api/chunky' do
        width = 960
        height = 640
        left = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::BLACK)
        right = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::BLACK)
        template = ChunkyPNG::Image.new(38, 19, ChunkyPNG::Color::BLACK)
        draw_text(template, "COBOL", "8x13B", ChunkyPNG::Color::WHITE)
        (0..19).each do |y|
            (0..38).each do |x|
                g = 255
                px = x * 8 * 3 + (rand() * 6).floor.to_i + 6
                py = y * 10 * 3 + (rand() * 10).floor.to_i + 10
                c = %w(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z).sample
                sep = (rand() * 6).floor.to_i + 2
                if (template.get_pixel(x, y) == ChunkyPNG::Color::WHITE)
                    sep = -6
                end
                draw_text(left, c, "6x10", ChunkyPNG::Color.rgba(g, 0, 0, 255), {:x => px, :y => py, :scale => 3})
                draw_text(right, c, "6x10", ChunkyPNG::Color.rgba(0, g, 0, 255), {:x => px + sep, :y => py, :scale => 3})
            end
        end
        png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::BLACK)
        (0...height).each do |y|
            (0...width).each do |x|
                a = ChunkyPNG::Color::to_truecolor_alpha_bytes(ChunkyPNG::Color::parse(left.get_pixel(x, y)))
                b = ChunkyPNG::Color::to_truecolor_alpha_bytes(ChunkyPNG::Color::parse(right.get_pixel(x, y)))
                png.set_pixel(x, y, ChunkyPNG::Color::rgba(a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]))
            end
        end
        respond_raw_with_mimetype(png.to_blob, 'image/png')

        # png = Image.new(960, 320) do |img|
        #     img.background_color = 'black'
        #     img.format = 'PNG'
        # end
        # drawing = Draw.new
        # drawing.annotate(png, 0, 0, 0, 0, "scumm".upcase) { |txt|
        #   txt.gravity = Magick::CenterGravity
        #   txt.text_antialias = false
        #   txt.pointsize = 240
        #   txt.fill = "#ffffff"
        #   txt.font = 'Droid-Sans-Bold'
        # }
        # pixels = png.get_pixels(0, 0, 960, 320)
        # # respond_raw_with_mimetype(png.to_blob, 'image/png')
        # width = 960
        # height = 320
        # eye_sep = 80
        # perlin = ChunkyPNG::Image.from_file('/static/images/perlin.png')
        # png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::BLACK)
        # template = ChunkyPNG::Image.new(width - eye_sep, height, ChunkyPNG::Color::BLACK)
        # draw_text(template, "COBOL", "8x13B", ChunkyPNG::Color::WHITE, {:scale => 20})
        # (0...width).each do |x|
        #     (0...height).each do |y|
        #         g = ChunkyPNG::Color::BLACK
        #         if x < eye_sep
        #             # g = (rand() * 256).floor.to_i
        #             g = perlin.get_pixel(x % 80, y % 80)
        #         else
        #             depth = 0
        #             x0 = x - eye_sep
        #             d = ((x - eye_sep / 2 - width / 2) ** 2 + (y - height / 2) ** 2) ** 0.5
        #             d *= 0.01
        #             x0 -= -d*d * 0.5
        #             if (pixels[y * 960 + x - eye_sep / 2] || Pixel.new(0, 0, 0, 1)).intensity > 0
        #             # if ((template.get_pixel(x0, y) || 0) >> 8) & 0xff > 0
        #                 x0 = x - eye_sep + 10
        #             end
        #             x0 += 10
        #             g = png.get_pixel(x0.to_i, y) || ChunkyPNG::Color::BLACK
        #         end
        #         png.set_pixel(x, y, g)
        #     end
        # end
        # respond_raw_with_mimetype(png.to_blob, 'image/png')
    end

end
