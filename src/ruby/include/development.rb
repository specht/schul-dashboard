class Main < Sinatra::Base
    def print_dev_stats()
        require_developer!
        dark = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User {dark: true})
            RETURN COUNT(u) AS userCount;
        END_OF_QUERY

        new_design = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User {new_design: true})
            RETURN COUNT(u) AS userCount;
        END_OF_QUERY

        StringIO.open do |io|
            io.puts "<h3>User, die Zugriff auf diese Seite haben</h3>"
            io.puts "<div class='row' style='margin-bottom: 15px;'><div class='col-md-12'>"
            io.puts "<table class='table narrow table-striped' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr><td>User</td></tr>"
            io.puts "</thead><tbody>"
            for tech_admin in DEVELOPERS.uniq.sort do
                next unless @@user_info[tech_admin]
                display_name = @@user_info[tech_admin][:display_name]
                nc_login = @@user_info[tech_admin][:nc_login]
                io.puts "<tr><td><code><img src='#{NEXTCLOUD_URL}/index.php/avatar/#{nc_login}/256' class='icon avatar-md'>&nbsp;#{display_name}</code></td></tr>"
            end
            io.puts "</tbody></table>"
            io.puts "</div></div>"
            io.puts "<h3>Statistiken</h3>"
            io.puts "<p>Anzahl der Nutzer, die das neue Design nutzen: #{new_design[0]["userCount"]}</p>"
            io.puts "<p>Anzahl der Nutzer, die den Dark-Mode nutzen: #{dark[0]["userCount"]}</p>"
            io.string
        end
    end
end
