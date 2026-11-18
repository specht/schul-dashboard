class Main < Sinatra::Base

    # AGs und Angebote (/angebote). An offer has one responsible person
    # (DEFINED_BY: whoever created it, or whom an admin assigned it to) and
    # may be shared with others who run offers (SHARED_WITH). Those edit it
    # like the responsible person (name and participants); deleting and
    # sharing stay with the responsible person (sharing also with admins).
    # Admins can assign an offer to someone else; an offer whose responsible
    # person is gone can be taken over (see /api/take_over_angebot).

    # still at school and allowed to run offers
    def angebot_manager?(email)
        !!(email && @@user_info[email] && user_has_role(email, :can_manage_angebote))
    end

    # the responsible person and the co-owners of an offer, nil if there is
    # no offer with this id
    def angebot_people(aid)
        row = neo4j_query(<<~END_OF_QUERY, :aid => aid).first
            MATCH (a:Angebot {id: $aid})-[:DEFINED_BY]->(ou:User)
            OPTIONAL MATCH (a)-[:SHARED_WITH]->(su:User)
            RETURN ou.email AS owner, collect(su.email) AS co_owners;
        END_OF_QUERY
        return nil if row.nil?
        {:owner => row['owner'], :co_owners => (row['co_owners'] || []).compact}
    end

    # the responsible person or a co-owner may edit an offer
    def require_angebot_editor!(aid)
        people = angebot_people(aid)
        assert(!people.nil?, 'no such angebot')
        email = @session_user[:email]
        assert(people[:owner] == email || people[:co_owners].include?(email), 'not allowed to edit this angebot')
        people
    end

    # the responsible person and the co-owners as names (students see
    # teachers by their official name, "Herr Dr. …"); only those still known
    def angebot_responsible_names(owner, co_owners, official)
        ([owner] + co_owners.sort).uniq.select { |email| @@user_info[email] }.map do |email|
            info = @@user_info[email]
            official ? ((info[:teacher] && info[:display_name_official]) || info[:display_name]) : info[:display_name]
        end
    end

    # all offers – or the one with the given id – for /angebote and the
    # answers of the API below: {:recipients, :aid, :info, :owner} plus
    # :co_owners where the offer is shared (left out otherwise, so that
    # today's page gets the same data as before)
    def get_angebote(only_aid = nil)
        if only_aid.nil?
            # first, purge all connections to users which no longer exist
            neo4j_query(<<~END_OF_QUERY).each do |row|
                MATCH (a:Angebot)<-[r:IS_PART_OF]->(u:User)
                RETURN DISTINCT u.email;
            END_OF_QUERY
                email = row['u.email']
                unless @@user_info[email]
                    neo4j_query(<<~END_OF_QUERY, :email => email)
                        MATCH (u:User {email: $email})-[r:IS_PART_OF]->(a:Angebot)
                        DELETE r;
                    END_OF_QUERY
                end
            end
        end
        angebote = neo4j_query(<<~END_OF_QUERY, :aid => only_aid).map { |x| {:info => x['a'], :recipient => x['u.email'], :owner => x['ou.email'] } }
            MATCH (a:Angebot)-[:DEFINED_BY]->(ou:User)
            WHERE $aid IS NULL OR a.id = $aid
            WITH a, ou
            OPTIONAL MATCH (u:User)-[r:IS_PART_OF]->(a)
            RETURN a, u.email, ou.email
            ORDER BY a.created DESC, a.id;
        END_OF_QUERY
        co_owners = {}
        neo4j_query(<<~END_OF_QUERY, :aid => only_aid).each do |row|
            MATCH (a:Angebot)-[:SHARED_WITH]->(u:User)
            WHERE $aid IS NULL OR a.id = $aid
            RETURN a.id, u.email;
        END_OF_QUERY
            next unless @@user_info[row['u.email']]
            (co_owners[row['a.id']] ||= []) << row['u.email']
        end
        temp = {}
        temp_order = []
        angebote.each do |x|
            unless temp[x[:info][:id]]
                temp[x[:info][:id]] = {
                    :recipients => [],
                    :aid => x[:info][:id],
                    :info => x[:info],
                    :owner => x[:owner],
                }
                temp_order << x[:info][:id]
            end
            # an offer without participants has none (not [null])
            temp[x[:info][:id]][:recipients] << x[:recipient] if x[:recipient] && @@user_info[x[:recipient]]
        end
        angebote = temp_order.map do |x|
            temp[x]
        end
        angebote.sort! do |a, b|
            a[:info][:name].downcase <=> b[:info][:name].downcase
        end
        angebote.each do |angebot|
            angebot[:recipients].sort! do |a, b|
                (@@user_info[a][:klasse] == @@user_info[b][:klasse]) ?
                (@@user_info[a][:last_name] <=> @@user_info[b][:last_name]) :
                (KLASSEN_ORDER.index(@@user_info[a][:klasse]) <=> KLASSEN_ORDER.index(@@user_info[b][:klasse]))
            end
            shared = co_owners[angebot[:aid]]
            angebot[:co_owners] = shared.uniq.sort if shared
        end
        angebote
    end

    def angebot_changed!
        trigger_update("_angebote_/#{@session_user[:email]}")
        Main.update_angebote_groups()
        Main.update_mailing_lists()
    end

    def link_angebot_recipients(aid, recipients)
        neo4j_query(<<~END_OF_QUERY, :aid => aid, :recipients => recipients.select { |x| x.is_a?(String) && @@user_info.include?(x) })
            MATCH (a:Angebot {id: $aid})
            WITH DISTINCT a
            MATCH (u:User)
            WHERE u.email IN $recipients
            MERGE (u)-[:IS_PART_OF]->(a);
        END_OF_QUERY
    end

    post '/api/save_angebot' do
        require_user_with_role!(:can_manage_angebote)
        data = parse_request_data(:required_keys => [:name, :recipients],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024)
        id = RandomTag.generate(12)
        timestamp = Time.now.to_i
        neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :name => data[:name])
            MATCH (u:User {email: $session_email})
            CREATE (a:Angebot {id: $id, name: $name})
            SET a.created = $timestamp
            SET a.updated = $timestamp
            CREATE (a)-[:DEFINED_BY]->(u)
            RETURN a;
        END_OF_QUERY
        link_angebot_recipients(id, data[:recipients])
        angebot_changed!
        respond(:ok => true, :angebot => get_angebote(id).first)
    end

    post '/api/update_angebot' do
        require_user_with_role!(:can_manage_angebote)
        data = parse_request_data(:required_keys => [:aid, :name, :recipients],
                                :types => {:recipients => Array},
                                :max_body_length => 1024 * 1024,
                                :max_string_length => 1024 * 1024)
        # the responsible person or a co-owner
        require_angebot_editor!(data[:aid])
        id = data[:aid]
        timestamp = Time.now.to_i
        transaction do
            neo4j_query_expect_one(<<~END_OF_QUERY, :timestamp => timestamp, :id => id, :name => data[:name])
                MATCH (a:Angebot {id: $id})
                SET a.updated = $timestamp
                SET a.name = $name
                WITH DISTINCT a
                OPTIONAL MATCH (u)-[r:IS_PART_OF]->(a)
                DELETE r
                WITH DISTINCT a
                RETURN a;
            END_OF_QUERY
            link_angebot_recipients(id, data[:recipients])
        end
        angebot_changed!
        respond(:ok => true, :angebot => get_angebote(id).first, :aid => id)
    end

    post '/api/delete_angebot' do
        require_user_with_role!(:can_manage_angebote)
        data = parse_request_data(:required_keys => [:aid])
        # only the responsible person (co-owners give up their part instead)
        people = angebot_people(data[:aid])
        assert(!people.nil? && people[:owner] == @session_user[:email], 'not allowed to delete this angebot')
        id = data[:aid]
        transaction do
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :id => id)
                MATCH (ou:User {email: $session_email})<-[:DEFINED_BY]-(a:Angebot {id: $id})
                DETACH DELETE a;
            END_OF_QUERY
        end
        angebot_changed!
        respond(:ok => true, :aid => data[:aid])
    end

    # Teilen: the responsible person (or an admin) lets someone else who runs
    # offers edit it as well
    post '/api/share_angebot' do
        require_user_with_role!(:can_manage_angebote)
        data = parse_request_data(:required_keys => [:aid, :email],
                                  :max_value_lengths => {:aid => 64, :email => 256})
        people = angebot_people(data[:aid])
        assert(!people.nil?, 'no such angebot')
        assert(people[:owner] == @session_user[:email] || admin_logged_in?, 'not allowed to share this angebot')
        email = data[:email].strip.downcase
        assert(angebot_manager?(email), 'cannot share with this user')
        assert(email != people[:owner], 'already responsible')
        neo4j_query_expect_one(<<~END_OF_QUERY, :aid => data[:aid], :email => email)
            MATCH (a:Angebot {id: $aid})
            MATCH (u:User {email: $email})
            MERGE (a)-[:SHARED_WITH]->(u)
            RETURN a.id;
        END_OF_QUERY
        respond(:ok => true, :angebot => get_angebote(data[:aid]).first)
    end

    # undoing it: the responsible person or an admin for anyone, a co-owner
    # for themselves ("Mitverantwortung abgeben")
    post '/api/unshare_angebot' do
        require_user_with_role!(:can_manage_angebote)
        data = parse_request_data(:required_keys => [:aid, :email],
                                  :max_value_lengths => {:aid => 64, :email => 256})
        people = angebot_people(data[:aid])
        assert(!people.nil?, 'no such angebot')
        email = data[:email].strip.downcase
        assert(people[:owner] == @session_user[:email] || admin_logged_in? || email == @session_user[:email], 'not allowed to unshare this angebot')
        neo4j_query(<<~END_OF_QUERY, :aid => data[:aid], :email => email)
            MATCH (a:Angebot {id: $aid})-[r:SHARED_WITH]->(u:User {email: $email})
            DELETE r;
        END_OF_QUERY
        respond(:ok => true, :angebot => get_angebote(data[:aid]).first)
    end

    # Zuweisen (admins): someone else who runs offers becomes responsible,
    # e.g. when an offer changes hands. The previous person stays a co-owner
    # if keep_previous is set and they are still at school.
    post '/api/assign_angebot' do
        require_admin!
        data = parse_request_data(:required_keys => [:aid, :email],
                                  :optional_keys => [:keep_previous],
                                  :types => {:keep_previous => Object},
                                  :max_value_lengths => {:aid => 64, :email => 256})
        assert([nil, true, false].include?(data[:keep_previous]))
        people = angebot_people(data[:aid])
        assert(!people.nil?, 'no such angebot')
        email = data[:email].strip.downcase
        assert(angebot_manager?(email), 'cannot assign to this user')
        assert(email != people[:owner], 'already responsible')
        previous = people[:owner]
        transaction do
            move_angebot_to(data[:aid], email)
            if data[:keep_previous] && angebot_manager?(previous)
                neo4j_query(<<~END_OF_QUERY, :aid => data[:aid], :email => previous)
                    MATCH (a:Angebot {id: $aid})
                    MATCH (u:User {email: $email})
                    MERGE (a)-[:SHARED_WITH]->(u);
                END_OF_QUERY
            end
        end
        respond(:ok => true, :angebot => get_angebote(data[:aid]).first)
    end

    # Übernehmen: an offer whose responsible person is no longer at school
    # (or may no longer run offers) can be taken over by one of its
    # co-owners, or by anyone who runs offers if no co-owner is left either –
    # so that an AG goes on without waiting for an admin.
    post '/api/take_over_angebot' do
        require_user_with_role!(:can_manage_angebote)
        data = parse_request_data(:required_keys => [:aid], :max_value_lengths => {:aid => 64})
        people = angebot_people(data[:aid])
        assert(!people.nil?, 'no such angebot')
        email = @session_user[:email]
        assert(!angebot_manager?(people[:owner]), 'the responsible person is still there')
        assert(people[:co_owners].include?(email) || people[:co_owners].none? { |x| angebot_manager?(x) }, 'a co-owner is still there')
        transaction do
            move_angebot_to(data[:aid], email)
        end
        respond(:ok => true, :angebot => get_angebote(data[:aid]).first)
    end

    # the offer's responsibility moves to email (who is no co-owner then)
    def move_angebot_to(aid, email)
        neo4j_query_expect_one(<<~END_OF_QUERY, :aid => aid, :email => email)
            MATCH (a:Angebot {id: $aid})-[r:DEFINED_BY]->(:User)
            MATCH (u:User {email: $email})
            DELETE r
            CREATE (a)-[:DEFINED_BY]->(u)
            WITH DISTINCT a, u
            OPTIONAL MATCH (a)-[s:SHARED_WITH]->(u)
            DELETE s
            RETURN a.id;
        END_OF_QUERY
    end

    # Neues Design: who is logged in, whether they are an admin and everyone
    # who may run offers (for Teilen and Zuweisen) for preview/angebote.js;
    # nothing for today's page
    def angebote_preview_html
        return '' unless ui_preview?
        managers = @@user_info.keys.select { |email| angebot_manager?(email) }.map do |email|
            info = @@user_info[email]
            {:email => email, :name => info[:display_name] || email, :sort => [info[:last_name].to_s.downcase, (info[:display_name] || email).downcase]}
        end.sort_by { |x| x[:sort] }.map { |x| {:email => x[:email], :name => x[:name]} }
        data = {:me => @session_user[:email], :admin => admin_logged_in?, :managers => managers}
        "\n<script>var pv_angebote = #{data.to_json.gsub('</', '<\\/')};</script>\n" +
        "<script src='#{preview_asset('/preview/angebote.js')}'></script>"
    end

    def get_angebote_for_session_user
        require_user!
        angebote = []
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]}).each do |row|
            MATCH (u:User {email: $email})-[:IS_PART_OF]->(a:Angebot)-[:DEFINED_BY]->(ou:User)
            OPTIONAL MATCH (a)-[:SHARED_WITH]->(su:User)
            RETURN a, ou.email, collect(su.email) AS co_owners;
        END_OF_QUERY
            angebot = row['a']
            # students see teachers by their official name ("Herr Dr. …"),
            # everyone who runs the offer
            names = angebot_responsible_names(row['ou.email'], (row['co_owners'] || []).compact, true)
            next if names.empty?
            angebote << {
                :owner => names.join(', '),
                :name => angebot[:name],
            }
        end
        angebote.sort! do |a, b|
            a[:name].downcase <=> b[:name].downcase
        end
        angebote
    end

    def get_angebote_for_email
        require_user_with_role!(:can_manage_angebote)
        angebote = {}
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (u:User)-[:IS_PART_OF]->(a:Angebot)-[:DEFINED_BY]->(ou:User)
            OPTIONAL MATCH (a)-[:SHARED_WITH]->(su:User)
            RETURN u.email, a.name, ou.email, collect(su.email) AS co_owners;
        END_OF_QUERY
            owner = row['ou.email']
            name = row['a.name']
            email = row['u.email']
            co_owners = (row['co_owners'] || []).compact
            names = [(@@user_info[owner] || {})[:display_name] || "(#{owner})"] +
                    angebot_responsible_names(owner, co_owners, false).drop(@@user_info[owner] ? 1 : 0)
            angebote[email] ||= []
            angebote[email] << {
                :owner => names.join(', '),
                :name => name,
            }
        end
        angebote
    end
end
