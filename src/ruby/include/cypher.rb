require 'chunky_png'
require 'wavefile'
# require 'rmagick'
# include Magick

CW_TR = [
    ".-", "-...", "-.-.", "-..", ".", "..-.", "--.", "....", "..",
    ".---", "-.-", ".-..", "--", "-.", "---", ".--.", "--.-",
    ".-.", "...", "-", "..-", "...-", ".--", "-..-", "-.--", "--.."
]

STEGO_TEXT = <<~EOS.gsub("\n", ' ').gsub(/\s+/, ' ')
    Steganography (/ˌstɛɡəˈnɒɡrəfi/) is the practice of representing information
    within another message or physical object, in such a manner that the presence
    of the information is not evident to human inspection. In computing/electronic
    contexts, a computer file, message, image, or video is concealed within another
    file, message, image, or video. The word steganography comes from Greek
    steganographia, which combines the words steganós (στεγανός), meaning "covered
    or concealed", and -graphia (γραφή) meaning "writing". The first recorded use
    of the term was in 1499 by Johannes Trithemius in his Steganographia, a treatise
    on cryptography and steganography, disguised as a book on magic. Generally, the
    hidden messages appear to be (or to be part of) something else: images, articles,
    shopping lists, or some other cover text. For example, the hidden message may be
    in invisible ink between the visible lines of a private letter. Some
    implementations of steganography that lack a shared secret are forms of security
    through obscurity, and key-dependent steganographic schemes adhere to Kerckhoffs's
    principle. The advantage of steganography over cryptography alone is that the
    intended secret message does not attract attention to itself as an object of
    scrutiny. Plainly visible encrypted messages, no matter how unbreakable they are,
    arouse interest and may in themselves be incriminating in countries in which
    encryption is illegal. Whereas cryptography is the practice of protecting the
    contents of a message alone, steganography is concerned with concealing the fact
    that a secret message is being sent and its contents. Steganography includes the
    concealment of information within computer files. In digital steganography,
    electronic communications may include steganographic coding inside of a transport
    layer, such as a document file, image file, program, or protocol. Media files are
    ideal for steganographic transmission because of their large size. For example,
    a sender might start with an innocuous image file and adjust the color of every
    hundredth pixel to correspond to a letter in the alphabet. The change is so subtle
    that someone who is not specifically looking for it is unlikely to notice the change.
EOS

def cw_pattern(word)
    pattern = ''
    word.each_char do |c|
        c = c.upcase
        ci = c.ord - 'A'.ord
        if c == ' '
            pattern += '       '
            while pattern.length % 8 != 0
                pattern += ' '
            end
        else
            cw = CW_TR[ci]
            (0...cw.size).each do |cwi|
                if cw[cwi] == '.'
                    pattern += '.'
                else
                    pattern += '...'
                end
                if cwi < cw.size - 1
                    pattern += ' '
                else
                    pattern += '   '
                end
            end
        end
    end
    pattern
end

class PixelFont
    def self.load_font(path)
        STDERR.puts "Loading font from #{path}..."
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

    def self.draw_text(png, s, font, color, options = {})
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

    def self.text_width(s, font, options = {})
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
end

class BitmapFont
    def self.load_font(path)
        @@fonts ||= {}
        return if @@fonts[path]
        @@fonts[path] = {}
        Dir[File.join(File.join('/app/cypher', path), '*.png')].each do |p|
            c = File.basename(p).sub('.png', '')
            b = ChunkyPNG::Image.from_file(p)
            @@fonts[path][c] = b
        end
    end

    def self.draw_text(png, s, font, x, y)
        self.load_font(font)
        s.each_char do |c|
            if @@fonts[font][c]
                png.compose!(@@fonts[font][c], x, y)
                x += @@fonts[font][c].width + 3
            elsif c == ' '
                x += @@fonts[font]['A'].width + 3
            end
        end
    end

    def self.text_width(s, font)
        self.load_font(font)
        width = 0
        s.each_char do |c|
            if @@fonts[font][c]
                width += @@fonts[font][c].width + 3
            elsif c == ' '
                width += @@fonts[font]['A'].width + 3
            end
        end
        width - 3
    end
end

class Main < Sinatra::Base
    MAX_CYPHER_LEVEL = 10

    CYPHER_LANGUAGES = %w(Ada Algol awk Bash Basic Cobol dBase Delphi Erlang Fortran
        Go Haskell Java Lisp Logo Lua MASM Modula Oberon Pascal Perl PHP
        Prolog Ruby Rust Scala Scumm Squeak Swift TeX ZPL)

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

    def line_for_lang(lang)
        [
            "Das naechste Loesungswort lautet #{lang}",
            "Das Passwort lautet #{lang}",
            "Versuch es mal mit #{lang}",
            "Wenn du #{lang} eingibst dann sollte es klappen",
            "#{lang} ist das naechste Passwort"
        ].sample
    end

    def get_next_cypher_password
        @cypher_next_password = nil
        srand(@cypher_seed)
        languages = CYPHER_LANGUAGES.shuffle
        if @cypher_level == 0
            lang = languages[@cypher_level]
            line = line_for_lang(lang)
            @cypher_next_password = lang
            @cypher_token = caesar(line, 3)
        elsif @cypher_level == 1
            lang = languages[@cypher_level]
            line = line_for_lang(lang)
            @cypher_next_password = lang
            @cypher_token = skytale(line, [3, 4, 5, 6].sample)
        elsif @cypher_level == 2
            lang = languages[@cypher_level]
            line = line_for_lang(lang)
            @cypher_next_password = lang
            @cypher_token = line
        elsif @cypher_level == 3
            lang = languages[@cypher_level]
            @cypher_next_password = lang
            @cypher_token = nil
        elsif @cypher_level == 4
            lang = languages[@cypher_level]
            @cypher_next_password = lang
            @cypher_token = nil
        elsif @cypher_level == 5
            lang = languages[@cypher_level]
            line = line_for_lang(lang)
            @cypher_next_password = lang
            @cypher_token = line
        elsif @cypher_level == 6
            lang = languages[@cypher_level]
            tag = Digest::SHA1.hexdigest("#{lang.downcase}-cypher").to_i(16).to_s(36)[0, 4]
            @cypher_next_password = lang
            @cypher_token = tag
        elsif @cypher_level == 7
            pin = (0..3).map { |x| rand(10).to_s }.join('')
            tag = ''
            provided_password = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})['provided']
                MATCH (u:User {email: $email})
                RETURN COALESCE(u.cypher_provided, '') AS provided;
            END_OF_QUERY
            srand(Time.now.to_i)
            provided_password = '    ' if provided_password.strip.empty?
            unless provided_password.nil?
                t = rand(5) + 1
                (0...4).each do |i|
                    t += rand(10) + 55
                    break unless provided_password[i] == pin[i]
                end
                tag = "Die Überprüfung der PIN dauerte #{t} µs."
            end
            @cypher_next_password = pin
            @cypher_token = tag
        elsif @cypher_level == 8
            lang = languages[@cypher_level]
            line = "Das naechste Loesungswort lautet #{lang}"
            @cypher_next_password = lang
            @cypher_token = line
        elsif @cypher_level == 9
            lang = languages[@cypher_level]
            line = line_for_lang(lang)
            @cypher_next_password = lang
            @cypher_token = line
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
        @tries_left = 3 - failed_cypher_tries
        if @cypher_level == 7
            @tries_left = 50 - failed_cypher_tries
        end
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
            result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :cypher_provided => provided_password })
                MATCH (u:User {email: $email})
                SET u.cypher_provided = $cypher_provided;
            END_OF_QUERY
            if provided_password.downcase == @cypher_next_password.downcase
                @cypher_level += 1
                result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :cypher_level => @cypher_level})
                    MATCH (u:User {email: $email})
                    SET u.cypher_level = $cypher_level,
                    u.failed_cypher_tries = 0
                    REMOVE u.cypher_provided;
                END_OF_QUERY
            else
                result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
                    MATCH (u:User {email: $email})
                    SET u.failed_cypher_tries = COALESCE(u.failed_cypher_tries, 0) + 1;
                END_OF_QUERY
                if @tries_left <= 1
                    result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
                        MATCH (u:User {email: $email})
                        SET u.cypher_level = 0, u.failed_cypher_tries = 0, u.cypher_name = ''
                        REMOVE u.cypher_provided;
                    END_OF_QUERY
                end
            end
        end
        unless provided_password.nil?
            debug "REDIRECTING!"
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
                        io.puts "<p class='text-danger'><b>Achtung!</b> Deine letzte Antwort war leider falsch. Du hast noch <b>#{@tries_left} Versuch#{@tries_left == 1 ? '' : 'e'}</b>, bevor du wieder von vorn beginnen musst.</p>"
                        io.puts "<hr />"
                    else
                        io.puts "<p class='text-danger'><b>Achtung!</b> Deine letzte Antwort war leider falsch.</p>"
                        io.puts "<hr />"
                    end
                end
                path = "/static/cypher/level_#{@cypher_level + 1}.html"
                if File.exist?(path)
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
            SET u.cypher_level = 0, u.failed_cypher_tries = 0, u.cypher_name = ''
            REMOVE u.cypher_provided;
        END_OF_QUERY
        respond(:alright => 'yeah')
    end

    get '/api/halpert' do
        require_user!
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.cypher_level, 0) AS cypher_level,
            u.cypher_seed AS cypher_seed,
            COALESCE(u.failed_cypher_tries, 0) AS failed_cypher_tries,
            COALESCE(u.cypher_name, '') AS cypher_name;
        END_OF_QUERY
        @cypher_level = result['cypher_level']
        @cypher_seed = result['cypher_seed']
        get_next_cypher_password()
        width = 960
        height = 480
        letters = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::BLACK)
        points = []
        (0..14).each do |y|
            (0..14).each do |x|
                px = x * 30 + 10 + 20
                py = y * 30 + 20
                c = %w(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z).sample
                points << [px, py, c]
            end
        end

        @cypher_token.gsub!(' ', '')

        code_spots = (0...points.size).to_a
        code_spots.shuffle!
        code_spots = code_spots[0, @cypher_token.size].sort
        debug code_spots.to_json
        (0...@cypher_token.size).each do |i|
            points[code_spots[i]][2] = @cypher_token[i].upcase
            points[code_spots[i]] << :topsecret
        end

        points.each do |p|
            BitmapFont::draw_text(letters, p[2], 'Alegreya-Sans-Regular/24', p[0] - (BitmapFont::text_width(p[2], 'Alegreya-Sans-Regular/24') / 2).to_i, p[1])
            if p[3] == :topsecret
                # BitmapFont::draw_text(letters, '_', 'Alegreya-Sans-Regular/36', p[0] + 480 - (BitmapFont::text_width('_', 'Alegreya-Sans-Regular/36') / 2).to_i, p[1] - 6)
                letters.rect(p[0] + 480 - 12, p[1] - 12, p[0] + 480 + 12, p[1] + 12, ChunkyPNG::Color.rgb(128, 188, 66))
            end
        end

        respond_raw_with_mimetype(letters.to_blob, 'image/png')
    end

    get '/api/chunky' do
        require_user!
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.cypher_level, 0) AS cypher_level,
            u.cypher_seed AS cypher_seed,
            COALESCE(u.failed_cypher_tries, 0) AS failed_cypher_tries,
            COALESCE(u.cypher_name, '') AS cypher_name;
        END_OF_QUERY
        @cypher_level = result['cypher_level']
        @cypher_seed = result['cypher_seed']
        get_next_cypher_password()
        width = 960
        height = 480
        left = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::BLACK)
        right = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::BLACK)
        template = ChunkyPNG::Image.new(38 + 100, 19, ChunkyPNG::Color::BLACK)
        @cypher_next_password.upcase!
        if @cypher_next_password.size < 6
            PixelFont::draw_text(template, @cypher_next_password, "8x13B", ChunkyPNG::Color::WHITE, {:x => 22 - @cypher_next_password.size * 4})
        elsif @cypher_next_password.size < 8
            PixelFont::draw_text(template, @cypher_next_password, "6x13", ChunkyPNG::Color::WHITE, {:x => 22 - @cypher_next_password.size * 3 + 1})
        else
            PixelFont::draw_text(template, @cypher_next_password, "5x7", ChunkyPNG::Color::WHITE, {:x => 22 - (@cypher_next_password.size * 2.5).to_i + 1, :y => 4})
        end
        (0..21).each do |y|
            (0..45).each do |x|
                c = %w(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z).sample
                px = x * 20 + (rand() * 6).floor.to_i + 26 - (BitmapFont::text_width(c, 'Alegreya-Sans-Regular/24') / 2).to_i
                py = y * 20 + (rand() * 10).floor.to_i + 10
                sep = (rand() * 4).floor.to_i + 2
                if (template.get_pixel(x, y - 4) == ChunkyPNG::Color::WHITE)
                    c = %w(A B D E F G H K M N O P Q R S U V W X Y Z).sample
                    px = x * 20 + (rand() * 2).floor.to_i + 26 - (BitmapFont::text_width(c, 'Alegreya-Sans-Regular/24') / 2).to_i
                    py = y * 20 + 10
                    sep = -6
                end
                BitmapFont::draw_text(left, c, 'Alegreya-Sans-Regular/24', px, py)
                BitmapFont::draw_text(right, c, 'Alegreya-Sans-Regular/24', px + sep, py)
            end
        end
        png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::BLACK)
        (0...height).each do |y|
            (0...width).each do |x|
                a = ChunkyPNG::Color::to_truecolor_alpha_bytes(ChunkyPNG::Color::parse(left.get_pixel(x, y)))
                b = ChunkyPNG::Color::to_truecolor_alpha_bytes(ChunkyPNG::Color::parse(right.get_pixel(x, y)))
                ag = (a[0] * 0.299 + a[1] * 0.587 + a[2] * 0.114).to_i
                bg = (b[0] * 0.299 + b[1] * 0.587 + b[2] * 0.114).to_i
                png.set_pixel(x, y, ChunkyPNG::Color::rgba(ag, bg, 0, 255))
            end
        end
        respond_raw_with_mimetype(png.to_blob, 'image/png')
    end

    get '/api/n_e_thing' do
        require_user!
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.cypher_level, 0) AS cypher_level,
            u.cypher_seed AS cypher_seed,
            COALESCE(u.failed_cypher_tries, 0) AS failed_cypher_tries,
            COALESCE(u.cypher_name, '') AS cypher_name;
        END_OF_QUERY
        @cypher_level = result['cypher_level']
        @cypher_seed = result['cypher_seed']
        get_next_cypher_password()
        scale = 2
        perlin = ChunkyPNG::Image.from_file('/static/images/perlin.png')
        @cypher_next_password.upcase!
        width = 960 * scale
        height = (@cypher_next_password.size * 72 + 72 + 36) * scale
        eye_sep = 80 * scale
        png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::BLACK)
        template = ChunkyPNG::Image.new(width - eye_sep, height, ChunkyPNG::Color::BLACK)
        offsets = (0...@cypher_next_password.size).to_a.shuffle
        @cypher_next_password.each_char.with_index do |c, i|
            BitmapFont::draw_text(template, c, 'Alegreya-Sans-Bold/72', (150 - BitmapFont::text_width(@cypher_next_password, 'Alegreya-Sans-Bold/72') / 2).to_i + BitmapFont::text_width(@cypher_next_password[0, i], 'Alegreya-Sans-Bold/72'), offsets[i] * 20)
        end
        # BitmapFont::draw_text(template, @cypher_next_password, 'Alegreya-Sans-Bold/72', (150 - BitmapFont::text_width(@cypher_next_password, 'Alegreya-Sans-Bold/72') / 2).to_i, 0)
        xs = (width / 2 - eye_sep / 2).to_i
        (0...height).each do |y|
            (0...width).each do |x|
                xf = x / scale
                yf = y / scale
                g = ChunkyPNG::Color::BLACK
                if x < eye_sep
                    g = perlin.get_pixel(x % 160, y % 160)
                else
                    depth = 0
                    x0 = x - eye_sep
                    d = ((x - eye_sep / 2 - width / 2) ** 2 + (y - height / 2) ** 2) ** 0.5
                    d *= 0.01
                    depth = d * d * 0.5
                    depth *= 0.5
                    depth = 0
                    if ((template.get_pixel(x0 / 6, y / 6 - 10) || 0) >> 8) & 0xff > 0
                        depth = 10
                    end
                    x0 += depth
                    g = png.get_pixel(x0.to_i, y) || ChunkyPNG::Color::BLACK
                end
                png.set_pixel(x, y, g)
            end
        end
        respond_raw_with_mimetype(png.to_blob, 'image/png')
    end

    get '/api/formula' do
        require_user!
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.cypher_level, 0) AS cypher_level,
            u.cypher_seed AS cypher_seed,
            COALESCE(u.failed_cypher_tries, 0) AS failed_cypher_tries,
            COALESCE(u.cypher_name, '') AS cypher_name;
        END_OF_QUERY
        @cypher_level = result['cypher_level']
        @cypher_seed = result['cypher_seed']
        get_next_cypher_password()

        samples = {}

        word = @cypher_next_password.upcase
        template = ChunkyPNG::Image.new(word.size * 8, 13, ChunkyPNG::Color::BLACK)
        PixelFont::draw_text(template, word, "8x13B", ChunkyPNG::Color::WHITE)
        l = (44100 * 60.0 / 100).floor
        (-36..36).each do |i|
            WaveFile::Reader.new("/app/cypher/pitch/pitch#{i >= 0 ? '+': ''}#{i}.wav") do |reader|
                buffer = reader.read(l)
                samples[i.to_s] = buffer.samples
            end
        end
        radio = []
        WaveFile::Reader.new("/app/cypher/pitch/radio.wav") do |reader|
            buffer = reader.read(reader.total_sample_frames)
            radio = buffer.samples
        end
        tone = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
        # tone = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19]
        count = 0
        WaveFile::Reader.new("/app/cypher/pitch/drums2.wav") do |drums_reader|
            WaveFile::Writer.new("/gen/my_file.wav", WaveFile::Format.new(:mono, :pcm_16, 44100)) do |writer|
                writer.write(WaveFile::Buffer.new(radio, WaveFile::Format.new(:mono, :pcm_16, 44100)))
                (0...word.size * 8).each do |x|
                    mix = samples['0'].dup.map { |x| 0 }
                    yc = 0
                    d = 100
                    (0...13).each do |y|
                        if template.get_pixel(x, y) == ChunkyPNG::Color::WHITE
                            (samples[(tone[y] + 15).to_i.to_s] || samples['0']).each.with_index do |a, i|
                                if i + yc * d < mix.size
                                    mix[i + yc * d] += a
                                end
                            end
                            yc += 1
                        end
                    end
                    drums_buffer = drums_reader.read(l)
                    drums = drums_buffer.samples
                    (0...l).each do |i|
                        if i < mix.size && i < drums.size
                            mix[i] += drums[i] * 0.7
                        end
                    end
                    mix = mix[0, l]
                    count += mix.size
                    buffer = WaveFile::Buffer.new(mix, WaveFile::Format.new(:mono, :pcm_16, 44100))
                    writer.write(buffer)
                end
                writer.write(WaveFile::Buffer.new(radio.reverse, WaveFile::Format.new(:mono, :pcm_16, 44100)))
            end
        end
        respond_raw_with_mimetype(File.read('/gen/my_file.wav'), 'audio/wav')
    end

    get '/api/cw' do
        require_user!
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.cypher_level, 0) AS cypher_level,
            u.cypher_seed AS cypher_seed,
            COALESCE(u.failed_cypher_tries, 0) AS failed_cypher_tries,
            COALESCE(u.cypher_name, '') AS cypher_name;
        END_OF_QUERY
        @cypher_level = result['cypher_level']
        @cypher_seed = result['cypher_seed']
        get_next_cypher_password()

        samples = {}

        debug "next password: #{@cypher_next_password}, cypher token: #{@cypher_token}"
        # @cypher_token = "DARGOBERT DACK EHRENMANN"
        pattern = ' ' * 32 + cw_pattern(@cypher_token) + ' ' * 32
        # pattern = ('.' + ' ' * 7) * 64
        # debug pattern

        l = (44100 * 60.0 / 125.0 / 4.0).floor
        word = @cypher_next_password.upcase
        WaveFile::Reader.new("/app/cypher/cw/cantina.wav") do |cantina_reader|
            WaveFile::Writer.new("/gen/my_file.wav", WaveFile::Format.new(:mono, :pcm_16, 44100)) do |writer|
                # writer.write(WaveFile::Buffer.new(radio, WaveFile::Format.new(:mono, :pcm_16, 44100)))
                (0...pattern.size).each do |x|
                    cantina_buffer = cantina_reader.read(l)
                    cantina = cantina_buffer.samples
                    # cantina.reverse!
                    if pattern[x] == '.'
                        (0...l).each do |i|
                            s = Math.sin(i.to_f / (44100.0 / 641.0) * (Math::PI * 2.0)) * 10000
                            f = (l - i) / 100.0
                            f = 1.0 if f > 1.0
                            s *= f
                            cantina[i] += s
                        end
                    end

                    # (0...l).each do |i|
                    #     if i < mix.size && i < drums.size
                    #         mix[i] += drums[i] * 0.7
                    #     end
                    # end
                    # mix = mix[0, l]
                    buffer = WaveFile::Buffer.new(cantina, WaveFile::Format.new(:mono, :pcm_16, 44100))
                    writer.write(buffer)
                end
                # writer.write(WaveFile::Buffer.new(radio.reverse, WaveFile::Format.new(:mono, :pcm_16, 44100)))
            end
        end
        respond_raw_with_mimetype(File.read('/gen/my_file.wav'), 'audio/wav')
    end


end
