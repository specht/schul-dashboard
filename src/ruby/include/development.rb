class Main < Sinatra::Base
    def print_dev_stats()
        require_user_with_role!(:developer)
        dark = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User {dark: true})
            RETURN COUNT(u) AS userCount;
        END_OF_QUERY

        new_design = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User {new_design: true})
            RETURN COUNT(u) AS userCount;
        END_OF_QUERY

        StringIO.open do |io|
            io.puts "<h3>Statistiken</h3>"
            io.puts "<p>Anzahl der Nutzer, die das neue Design nutzen: #{new_design[0]["userCount"]}</p>"
            io.puts "<p>Anzahl der Nutzer, die den Dark-Mode nutzen: #{dark[0]["userCount"]}</p>"
            io.puts "<h3>Phishing Status</h3>"
            io.puts "<code>"
            io.puts "<p>PHISHING_HINT_START = '#{PHISHING_HINT_START}'<br>PHISHING_HINT_END = '#{PHISHING_HINT_END}'</p>"
            io.puts "<p>PHISHING_START = '#{PHISHING_START}'<br>PHISHING_END = '#{PHISHING_END}'</p>"
            io.puts "<p>PHISHING_POLL_RUN_ID = '#{PHISHING_POLL_RUN_ID}'</p>"
            io.puts "<p>PHISHING_RECEIVING_DATE = '#{PHISHING_RECEIVING_DATE}'</p>"
            io.puts "</code>"
            io.string
        end
    end
end
