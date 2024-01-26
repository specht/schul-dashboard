class Main < Sinatra::Base
    def print_dev_stats()
        require_development!
        dark = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User {dark: true})
            RETURN COUNT(u) AS userCount;
        END_OF_QUERY

        new_design = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User {new_design: true})
            RETURN COUNT(u) AS userCount;
        END_OF_QUERY

        StringIO.open do |io|
            io.puts "<p>Anzahl der Nutzer, die das neue Design nutzen: #{new_design[0]["userCount"]}</p>"
            io.puts "<p>Anzahl der Nutzer, die den Dark-Mode nutzen: #{dark[0]["userCount"]}</p>"
            io.string
        end
    end
end
