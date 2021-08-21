require 'digest/md5'

# https://gist.githubusercontent.com/mecampbellsoup/7001539/raw/366a43c6dc7aea76dbe2357173e3fc7e0f7407f1/roman_numerals.rb

class Integer

  @@values = {
    1=>"I",
    4=>"IV",
    5=>"V",
    9=>"IX",
    10=>"X",
    40=>"XL",
    50=>"L",
    90=>"XC",
    100=>"C",
    400=>"CD",
    500=>"D",
    900=>"CM",
    1000=>"M"
  }

  def to_roman_descending #this one requires numeral-arabic pairs in descending order, i.e. 1000=>"M" on down
    return 0 if self == 0

    roman = ""
    integer = self
    @@values.each do |k,v|
      until integer < k
        roman << v
        integer -= k
      end
    end
    roman
  end

  def to_roman
    integer = self
    roman = ""

    while integer > 0
      if @@values[integer]
        roman += @@values[integer]
        return roman
      end

      roman += @@values[next_lower_key(integer)] # increment the roman numeral string here
      integer -= next_lower_key(integer) # decrement the arabic integer here
    end
  end

  def next_lower_key(integer)
    arabics = @@values.keys
    next_lower_index = (arabics.push(integer).sort.index(integer))-1
    arabics[next_lower_index]
  end
end

class Main < Sinatra::Base
    MAX_HACK_LEVEL = 10

    NAMES = %w(babbage boole catmull cerf chomksy codd dijkstra
        engelbart feinler hamilton hamming hejlsberg hopper kay knuth lamport
        lovelace minsky ritchie stroustrup thompson torvalds turing wirth zuse)

    FRUIT = %w(apfel birne tomate kiwi melone ananas kartoffel zitrone orange salat)

    SPACE_EVENTS = {
        '1957-10-04' => ['4. Oktober 1957', 'Am __DATE__ startete <b>Sputnik 1</b>, der erste künstliche Satellit, in die Umlaufbahn der Erde.'],
        '1957-11-03' => ['3. November 1957', 'Am __DATE__ startete <b>Sputnik 2</b> in die Umlaufbahn der Erde. An Bord befand sich <b>Laika</b>, das erste Tier im Weltraum.'],
        '1959-10-07' => ['7. Oktober 1959', 'Am __DATE__ sendete <b>Luna 3</b> die ersten Bilder von der Rückseite des Mondes.'],
        '1961-04-12' => ['12. April 1961', 'Am __DATE__ flog <b>Juri Gagarin</b> als erster Mensch in den Weltraum.'],
        '1962-12-14' => ['14. Dezember 1962', 'Am __DATE__ sendete <b>Mariner 2</b> erstmals Daten von der Venus zur Erde.'],
        '1963-06-16' => ['16. Juni 1963', 'Am __DATE__ flog <b>Walentina Tereschkowa</b> als erste Frau ins Weltall.'],
        '1965-03-18' => ['18. März 1965', 'Am __DATE__ unternahm <b>Alexei Leonow</b> den ersten Weltraumspaziergang.'],
    }
    PRIMES = %w(2	3	5	7	11	13	17	19	23	29
        31	37	41	43	47	53	59	61	67	71
        73	79	83	89	97	101	103	107	109	113
        127	131	137	139	149	151	157	163	167	173
        179	181	191	193	197	199	211	223	227	229
        233	239	241	251	257	263	269	271	277	281
        283	293	307	311	313	317	331	337	347	349
        353	359	367	373	379	383	389	397	401	409
        419	421	431	433	439	443	449	457	461	463
        467	479	487	491	499	503	509	521	523	541
        547	557	563	569	571	577	587	593	599	601
        607	613	617	619	631	641	643	647	653	659
        661	673	677	683	691	701	709	719	727	733
        739	743	751	757	761	769	773	787	797	809
        811	821	823	827	829	839	853	857	859	863
        877	881	883	887	907	911	919	929	937	941
        947	953	967	971	977	983	991	997).map { |x| x.to_i }
    def get_next_password
        @hack_next_password = nil
        srand(@hack_seed)
        if @hack_level == 0
            names = NAMES.shuffle
            @hack_next_password = names[@hack_level]
        elsif @hack_level == 1
            number = [1, 2].sample * 1000 + [1,2,3,4,5,6,7,8,9].sample * 100 + [1,2,3,4,5,6,7,8,9].sample * 10 + [1,2,3,4,5,6,7,8,9].sample
            @hack_next_password = number.to_roman.downcase
            @hack_token = "#{number}"
        elsif @hack_level == 2
            names = NAMES.shuffle
            @hack_next_password = names[@hack_level]
        elsif @hack_level == 3
            notes = [['C', 'Cis', 'D', 'Es', 'E', 'F', 'Fis', 'G', 'As', 'A', 'B', 'H'],
                     ['c', 'cis', 'd', 'es', 'e', 'f', 'fis', 'g', 'as', 'a', 'b', 'h']]

            index = (0...(notes[0].size)).to_a.sample
            mode = (0..1).to_a.sample
            chord = "#{notes[mode][index]}-#{mode == 0 ? 'Dur' : 'Moll'}"
            a = (index + ((mode == 0) ? 4 : 3) + [1, 11].sample) % 12
            b = (index + ((mode == 0) ? 4 : 3)) % 12
            c = (index + 7 + [1, 11].sample) % 12
            d = (index + [1, 11].sample) % 12

            @hack_next_password = notes[1][b]
            a, b, c, d = *([a, b, c, d].shuffle)
            @hack_description = "<span style='font-size: 150%;'><b>#{notes[1][a]}</b>, <b>#{notes[1][b]}</b>, <b>#{notes[1][c]}</b> oder <b>#{notes[1][d]}</b></span>"
            @hack_token = chord
        elsif @hack_level == 4
            names = NAMES.shuffle
            @hack_next_password = names[@hack_level]
        elsif @hack_level == 5
            space_events = SPACE_EVENTS.keys.shuffle
            date = space_events.first
            @hack_token = SPACE_EVENTS[date].first
            @hack_description = "#{SPACE_EVENTS[date][1].gsub('__DATE__', "<b>#{SPACE_EVENTS[date].first}</b>")} Wie viele Tage sind seitdem vergangen?"
            @hack_next_password = (Date.today - Date.parse(date)).to_i.to_s
        elsif @hack_level == 6
            ascii = '@#$%&*()[]{}'.split('').shuffle
            @hack_token = ascii.first
            @hack_next_password = sprintf('%02x', ascii.first.ord)
        elsif @hack_level == 7
            primes = PRIMES.shuffle
            ps = primes[0, 6]
            p = ps.sample
            @hack_token = ps.inject(1) { |_, x| _ * x } * p
            @hack_next_password = p.to_s
        elsif @hack_level == 8
            names = NAMES.shuffle
            @hack_next_password = names[@hack_level]
            response.headers['X-Dashboard-Hackers-Passwort'] = @hack_next_password
        elsif @hack_level == 9
            fruit = FRUIT.shuffle
            @hack_next_password = fruit.first
            @hack_token = Digest::MD5.hexdigest(@hack_next_password)
        end
        @hack_next_password
    end

    def hack_content 
        require_user!
        parts = request.env['REQUEST_PATH'].split('/')
        provided_password = (parts[2] || '').strip.downcase
        provided_password = nil if provided_password.empty?
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: {email}})
            RETURN COALESCE(u.hack_level, 0) AS hack_level, 
            u.hack_seed AS hack_seed,
            COALESCE(u.failed_tries, 0) AS failed_tries,
            COALESCE(u.hack_name, '') AS hack_name;
        END_OF_QUERY
        @hack_level = result['hack_level']
        @hack_seed = result['hack_seed']
        @hack_name = result['hack_name'].strip
        failed_tries = result['failed_tries']
        tries_left = 3 - failed_tries
        if @hack_seed.nil? || (@hack_level == 0 && provided_password.nil?)
            @hack_seed = Time.now.to_i
            result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :hack_seed => @hack_seed})
                MATCH (u:User {email: {email}})
                SET u.hack_seed = {hack_seed};
            END_OF_QUERY
        end
        
        get_next_password()

        STDERR.puts "HACK // #{@session_user[:email]} // level: #{@hack_level}, seed: #{@hack_seed}, provided: #{provided_password}#{provided_password.nil? ? '(nil)':''}, next password: #{@hack_next_password}#{@hack_next_password.nil? ? '(nil)':''}"

        unless provided_password.nil? || @hack_next_password.nil?
            if provided_password == @hack_next_password
                @hack_level += 1
                result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :hack_level => @hack_level})
                    MATCH (u:User {email: {email}})
                    SET u.hack_level = {hack_level},
                    u.failed_tries = 0;
                END_OF_QUERY
            else
                result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
                    MATCH (u:User {email: {email}})
                    SET u.failed_tries = COALESCE(u.failed_tries, 0) + 1;
                END_OF_QUERY
                if tries_left <= 1
                    result = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
                        MATCH (u:User {email: {email}})
                        SET u.hack_level = 0, u.failed_tries = 0, u.hack_name = '';
                    END_OF_QUERY
                end
            end
        end
        unless provided_password.nil?                
            redirect "#{WEB_ROOT}/h4ck", 302
        end

        get_next_password()

        StringIO.open do |io|
            io.puts "<p style='text-align: left; margin-top: 0;'><b>#{@session_user[:first_name]}</b> &lt;#{@session_user[:email]}&gt;</p>"
            if @hack_level == MAX_HACK_LEVEL
                # io.puts "<p style='float: right; margin-top: 0;'><a href='/hackers'>=&gt; Hall of Fame</a></p>"
                io.puts File.read('/static/hack/hall_of_fame.html')
                result = neo4j_query(<<~END_OF_QUERY)
                    MATCH (u:User)
                    WHERE COALESCE(u.hack_level, 0) > 0
                    RETURN u.email, u.hack_level, COALESCE(u.hack_name, '') AS hack_name
                END_OF_QUERY
                io.puts "<p>"
                io.puts "Bisher #{result.size == 1 ? 'hat' : 'haben'} <b>#{result.size} Hacker:in#{result.size == 1 ? '' : 'nen'}</b> versucht, die Aufgaben zu lösen."
                histogram = {}
                names = []
                result.each do |row|
                    histogram[row['u.hack_level']] ||= []
                    histogram[row['u.hack_level']] << row['u.email']
                    names << row['hack_name'] unless row['hack_name'].strip.empty?
                end
                names.sort!
                parts = []
                histogram.keys.sort.each do |level|
                    parts << "<b>#{histogram[level].size} Person#{histogram[level].size == 1 ? '' : 'en'}</b> in <b>Level #{level}</b>"
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
                io.puts "<span class='name-pref' data-name=''>[#{@hack_name == '' ? 'x': ' '}] Ich möchte <b>nicht</b> aufgelistet werden.</span><br />"
                possible_names.each do |name|
                    io.puts "<span class='name-pref' data-name=\"#{name}\">[#{@hack_name == name ? 'x': ' '}] Ich möchte als <b>»#{name}«</b> erscheinen.</span><br />"
                end
                io.puts "<span class='hack-reset text-danger'>[!] Ich möchte meinen <b>Fortschritt löschen</b> und von vorn beginnen.</span>"
                io.puts "<span class='text-danger' id='hack_reset_confirm' style='display: none;'><br />&nbsp;&nbsp;&nbsp;&nbsp;Bist du sicher? <span id='hack_reset_confirm_yes'><b>[Ja]</b></span> <span id='hack_reset_confirm_no'><b>[Nein]</b></span></span>"
                io.puts "</p>"
                io.puts "<h2><b>Hall of Fame</b></h2>"
                names.each do |name|
                    io.puts "<p class='name'>#{name}</p>"
                end
            else
                io.puts File.read('/static/hack/title.html').gsub('#{next_hack_level}', (@hack_level + 1).to_s)
                if failed_tries == 0
                    if @hack_level > 0
                        io.puts "<p><b>Gut gemacht!</b></p>"
                        io.puts "<hr />"
                    end
                else
                    if @hack_level > 0
                        tries_left = 3 - failed_tries
                        io.puts "<p class='text-danger'><b>Achtung!</b> Deine letzte Antwort war leider falsch. Du hast noch <b>#{tries_left} Versuch#{tries_left == 1 ? '' : 'e'}</b>, bevor du wieder von vorn beginnen musst.</p>"
                        io.puts "<hr />"
                    else
                        io.puts "<p class='text-danger'><b>Achtung!</b> Deine letzte Antwort war leider falsch.</p>"
                        io.puts "<hr />"
                    end
                end
                path = "/static/hack/level_#{@hack_level + 1}.html"
                if File.exists?(path)
                    io.puts File.read(path)
                end
                io.puts File.read('/static/hack/form.html')
            end
            io.string
        end
    end

    post '/api/hack_set_name' do
        require_user!
        data = parse_request_data(:required_keys => [:name])
        neo4j_query("MATCH (u:User {email: {email}}) SET u.hack_name = {name};", {:email => @session_user[:email], :name => data[:name]})
        display_name = @session_user[:display_name]
        deliver_mail(data[:name]) do
            to WEBSITE_MAINTAINER_EMAIL
            bcc SMTP_FROM
            from SMTP_FROM
            
            subject "H4CK: #{display_name}"
        end        
        respond(:alright => 'yeah')
    end

    post '/api/hack_reset' do
        require_user!
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: {email}})
            SET u.hack_level = 0, u.failed_tries = 0, u.hack_name = '';
        END_OF_QUERY
        respond(:alright => 'yeah')
    end

end
