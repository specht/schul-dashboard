# Groups of students that plan something together: Projekttage, Lab 8,
# Lab 9 and the 5th exam component (Pk5). The modules differ in their fields
# (update routes, history – see projekte.rb, lab8.rb, lab9.rb, pk5.rb), but
# forming the group works the same everywhere and lives here:
#
#   (group:Label)-[:BELONGS_TO]->(:User)      members, at most one group per kind
#   (group)-[:INVITATION_FOR]->(:User)        pending invitations
#   (:User)<-[:BY]-(:ChangeLabel)-[:TO]->(group)   history entries
#
# A group is created with MERGE on the first save or invitation of a student
# and joined by accepting an invitation – which takes the student out of
# every other group of the same kind.

class Main < Sinatra::Base
    # text, title and button of the question before switching groups
    PROJEKT_SWITCH_CONFIRMATION = ['Du bist schon in einem Projekt oder hast ein eigenes angelegt. Wenn du die Einladung annimmst, wechselst du in das neue Projekt – dein bisheriges wird dir dann nicht mehr angezeigt.', 'Projekt wechseln?', 'Projekt wechseln']

    # key => configuration; the key is part of the route names
    # (/api/send_invitation_for_<key>, /api/accept_<key>_invitation, …)
    STUDENT_GROUPS = {
        'projekttage' => {
            :label => 'Projekttage',
            :change_label => 'ProjekttageChange',
            :manager_role => :can_manage_projekttage,
            :eligible => lambda { |user_info, email| email_is_projekttage_organizer?(user_info, email) },
            :editable => lambda { !$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit) },
            :incoming => 'für ein gemeinsames Projekt',
            :outgoing => 'für dein Projekt',
            :datalist => 'li_sus_q1',
            :switch_confirmation => PROJEKT_SWITCH_CONFIRMATION,
        },
        'lab8_projekt' => {
            :label => 'Lab8Projekt',
            :change_label => 'Lab8ProjektChange',
            :manager_role => :can_manage_lab8,
            :eligible => lambda { |user_info, email| email_is_eligible_for_lab8?(user_info, email) },
            :editable => lambda { true },
            :incoming => 'für ein gemeinsames Lab 8-Projekt',
            :outgoing => 'für dein Lab 8-Projekt',
            :datalist => 'li_sus_q1',
            :switch_confirmation => PROJEKT_SWITCH_CONFIRMATION,
        },
        'lab9_projekt' => {
            :label => 'Lab9Projekt',
            :change_label => 'Lab9ProjektChange',
            :manager_role => :can_manage_lab9,
            :eligible => lambda { |user_info, email| email_is_eligible_for_lab9?(user_info, email) },
            :editable => lambda { true },
            :incoming => 'für ein gemeinsames Lab 9-Projekt',
            :outgoing => 'für dein Lab 9-Projekt',
            :datalist => 'li_sus_q1',
            :switch_confirmation => PROJEKT_SWITCH_CONFIRMATION,
        },
        'pk5' => {
            :label => 'Pk5',
            :change_label => 'Pk5Change',
            :manager_role => :oko,
            :eligible => lambda { |user_info, email| (user_info[email] || {})[:klasse] == PK5_CURRENT_KLASSE },
            :editable => lambda { !$pk5.phases[$pk5.get_current_phase][:flags].include?(:no_sus_edit) },
            :incoming => 'für eine Gruppenprüfung',
            :outgoing => 'für eine Gruppenprüfung',
            :datalist => 'li_sus_q2',
            :switch_confirmation => ['Du hast schon Angaben zu deiner Präsentationsprüfung gemacht oder bist in einer anderen Gruppe. Wenn du die Einladung annimmst, wechselst du in die neue Gruppe – deine bisherigen Angaben werden dir dann nicht mehr angezeigt.', 'Gruppe wechseln?', 'Gruppe wechseln'],
        },
    }

    def student_group(key)
        group = STUDENT_GROUPS[key]
        assert(!group.nil?, "unknown student group #{key}")
        group
    end

    # Takes a write lock on the student's user node until the end of the
    # current transaction. Concurrent requests for the same student (double
    # clicks, two saves at once) then run one after another, so MERGE can't
    # create a second group and an invitation can't be accepted twice.
    def lock_student_for_group_change!(email)
        neo4j_query_expect_one(<<~END_OF_QUERY, {:email => email})
            MATCH (u:User {email: $email})
            SET u._group_lock = true
            REMOVE u._group_lock
            RETURN u.email;
        END_OF_QUERY
    end

    def student_has_group?(key, email)
        label = student_group(key)[:label]
        !neo4j_query(<<~END_OF_QUERY, {:email => email}).to_a.empty?
            MATCH (p:#{label})-[:BELONGS_TO]->(:User {email: $email})
            RETURN p LIMIT 1;
        END_OF_QUERY
    end

    # Who may act for sus_email: the student themselves or a manager of the
    # module; with check_student also whether the student takes part and
    # whether the current phase allows changes.
    def assert_student_group_access!(group, sus_email, check_student: true)
        if user_with_role_logged_in?(group[:manager_role])
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        return unless check_student
        assert(group[:eligible].call(@@user_info, sus_email))
        assert(group[:editable].call)
    end

    def add_student_group_change!(group, member_email, attributes)
        neo4j_query_expect_one(<<~END_OF_QUERY, {:member_email => member_email, :editor_email => @session_user[:email], :attributes => attributes.merge(:ts => Time.now.to_i).transform_keys(&:to_s)})
            MATCH (eu:User {email: $editor_email})
            MATCH (p:#{group[:label]})-[:BELONGS_TO]->(:User {email: $member_email})
            CREATE (eu)<-[:BY]-(c:#{group[:change_label]})-[:TO]->(p)
            SET c += $attributes
            RETURN p;
        END_OF_QUERY
    end

    # sus_email invites other_email into their group (created if needed).
    def invite_into_student_group!(group, sus_email, other_email)
        label = group[:label]
        assert(sus_email != other_email)
        transaction do
            lock_student_for_group_change!(sus_email)
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})
                MATCH (u:User {email: $sus_email})
                MERGE (p:#{label})-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            # no invitation of a member, no second invitation
            rows = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email}).to_a
                MATCH (:User {email: $sus_email})<-[:BELONGS_TO]-(p:#{label})
                MATCH (ou:User {email: $other_email})
                WHERE (p)-[:BELONGS_TO]->(ou) OR (p)-[:INVITATION_FOR]->(ou)
                RETURN p LIMIT 1;
            END_OF_QUERY
            assert(rows.empty?, 'already a member or invited')
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:#{label})-[:BELONGS_TO]->(:User {email: $sus_email})
                MATCH (ou:User {email: $other_email})
                CREATE (p)-[:INVITATION_FOR]->(ou);
            END_OF_QUERY
            add_student_group_change!(group, sus_email, {:type => 'invite_sus', :other_email => other_email})
        end
    end

    def withdraw_student_group_invitation!(group, sus_email, other_email)
        transaction do
            rows = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email}).to_a
                MATCH (p:#{group[:label]})-[:BELONGS_TO]->(:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(:User {email: $other_email})
                DELETE r
                RETURN p;
            END_OF_QUERY
            assert(rows.size > 0)
            add_student_group_change!(group, sus_email, {:type => 'uninvite_sus', :other_email => other_email})
        end
    end

    # sus_email accepts the invitation into other_email's group and leaves
    # every other group of this kind. Returns :joined, or :already_member if
    # the invitation had already been accepted (second click); fails if there
    # is no invitation.
    def accept_student_group_invitation!(group, sus_email, other_email)
        label = group[:label]
        assert(sus_email != other_email)
        transaction do
            lock_student_for_group_change!(sus_email)
            # grouped by p: without an invitation there is no row at all
            joined = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email}).to_a
                MATCH (ou:User {email: $other_email})<-[:BELONGS_TO]-(p:#{label})-[r:INVITATION_FOR]->(u:User {email: $sus_email})
                WITH p, u, collect(r) AS invitations
                LIMIT 1
                FOREACH (x IN invitations | DELETE x)
                MERGE (p)-[:BELONGS_TO]->(u)
                WITH p, u
                OPTIONAL MATCH (u)<-[old:BELONGS_TO]-(op:#{label})
                WHERE op <> p
                WITH p, collect(old) AS old_memberships
                FOREACH (x IN old_memberships | DELETE x)
                RETURN size(old_memberships) AS left_groups;
            END_OF_QUERY
            if joined.empty?
                member = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email}).to_a
                    MATCH (:User {email: $other_email})<-[:BELONGS_TO]-(p:#{label})-[:BELONGS_TO]->(:User {email: $sus_email})
                    RETURN p LIMIT 1;
                END_OF_QUERY
                assert(!member.empty?, 'no invitation')
                next :already_member
            end
            add_student_group_change!(group, other_email, {:type => 'accept_invitation', :email => sus_email})
            :joined
        end
    end

    def reject_student_group_invitation!(group, sus_email, other_email)
        transaction do
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (:User {email: $other_email})<-[:BELONGS_TO]-(p:#{group[:label]})-[r:INVITATION_FOR]->(:User {email: $sus_email})
                DELETE r;
            END_OF_QUERY
            add_student_group_change!(group, other_email, {:type => 'reject_invitation', :email => sus_email})
        end
    end

    # invitations to user_email, with buttons to accept or reject them
    def print_pending_student_group_invitations_incoming(key, user_email)
        group = student_group(key)
        invitations = neo4j_query(<<~END_OF_QUERY, {:email => user_email}).map { |row| row['emails'] }
            MATCH (ou:User)<-[:BELONGS_TO]-(p:#{group[:label]})-[:INVITATION_FOR]->(:User {email: $email})
            WITH p, collect(ou.email) AS emails
            RETURN emails;
        END_OF_QUERY
        return '' if invitations.empty?
        StringIO.open do |io|
            io.puts "<hr>"
            invitations.each do |emails|
                io.puts "<p>Du hast eine Einladung von <strong>#{join_with_sep(emails.map { |x| @@user_info[x][:display_name]}, ', ', ' und ')}</strong> #{group[:incoming]} erhalten.</p>"
                io.puts "<p>"
                io.puts "<button class='btn btn-success bu-accept-invitation' data-email='#{emails.first}'><i class='fa fa-check'></i>&nbsp;&nbsp;Einladung annehmen</button>"
                io.puts "<button class='btn btn-danger bu-reject-invitation' data-email='#{emails.first}'><i class='fa fa-times'></i>&nbsp;&nbsp;Einladung ablehnen</button>"
                io.puts "</p>"
            end
            io.puts "<hr>"
            io.string
        end
    end

    # invitations sent from user_email's group, with buttons to withdraw them
    def pending_student_group_invitations_outgoing(group, user_email)
        emails = neo4j_query(<<~END_OF_QUERY, {:email => user_email}).map { |row| row['u.email'] }
            MATCH (:User {email: $email})<-[:BELONGS_TO]-(p:#{group[:label]})-[:INVITATION_FOR]->(u:User)
            RETURN u.email;
        END_OF_QUERY
        return '' if emails.empty?
        StringIO.open do |io|
            io.puts "<hr>"
            emails.each do |email|
                io.puts "<p>Du hast <strong>#{@@user_info[email][:display_name]}</strong> #{group[:outgoing]} eingeladen.</p>"
                io.puts "<p>"
                io.puts "<button class='btn btn-danger bu-delete-invitation' data-email='#{email}'><i class='fa fa-times'></i>&nbsp;&nbsp;Einladung zurücknehmen</button>"
                io.puts "</p>"
            end
            io.puts "<hr>"
            io.string
        end
    end

    # The script for inviting, withdrawing, accepting and rejecting on the
    # module's page (#modal_add_sus, #div_history, the buttons above).
    def print_student_group_invitation_script(key, user_email)
        group = student_group(key)
        already_in_group = user_email == @session_user[:email] && student_has_group?(key, user_email)
        switch_text, switch_title, switch_confirm = group[:switch_confirmation]
        <<~HTML
            <script type='text/javascript'>
            window.addEventListener('load', function() {
                const sus_email = #{user_email.to_json};
                function refresh_history(on_done) {
                    api_call('/api/my_#{key}_history', {sus_email: sus_email}, function(response) {
                        if (response.success) {
                            $('#div_history').html(response.html);
                            if (on_done) on_done();
                        }
                    });
                }
                $('#bu_add_sus').on('click', function(e) {
                    api_call('/api/pending_#{key}_invitations_outgoing', {sus_email: sus_email}, function(response) {
                        if (response.success) {
                            $('#div_pending_invitations').html(response.html);
                            $('#ti_add_sus').val('');
                            $('#modal_add_sus').modal('show');
                            $('#ti_add_sus').focus();
                            $('#div_pending_invitations .bu-delete-invitation').on('click', function(e) {
                                let other_email = $(e.currentTarget).data('email');
                                api_call('/api/delete_invitation_for_#{key}', {sus_email: sus_email, other_email: other_email}, function(response2) {
                                    if (response2.success) {
                                        refresh_history(function() { $('#modal_add_sus').modal('hide'); });
                                    }
                                });
                            });
                        }
                    });
                });
                $('#ti_add_sus').on('change keyup', function(e) {
                    let name = $('#ti_add_sus').val().trim();
                    let found_name = false;
                    for (let entry of $('datalist##{group[:datalist]}').find('option')) {
                        if (entry.value === name) {
                            found_name = true;
                            break;
                        }
                    }
                    $('#bu_send_sus_invitation').prop('disabled', !found_name);
                });
                $('#bu_send_sus_invitation').on('click', function(e) {
                    api_call('/api/send_invitation_for_#{key}', {sus_email: sus_email, name: $('#ti_add_sus').val().trim()}, function(response) {
                        if (response.success) {
                            $('#modal_add_sus').modal('hide');
                            refresh_history();
                        }
                    });
                });
                // accepting moves the student out of a group they're already in
                const already_in_group = #{already_in_group ? 'true' : 'false'};
                $('.bu-accept-invitation').on('click', function(e) {
                    let other_email = $(e.currentTarget).data('email');
                    let accept = function() {
                        api_call('/api/accept_#{key}_invitation', {sus_email: sus_email, other_email: other_email}, function(response) {
                            if (response.success) {
                                window.location.reload();
                            }
                        });
                    };
                    if (already_in_group) {
                        dashboardConfirm(#{switch_text.to_json}, accept, {title: #{switch_title.to_json}, confirm: #{switch_confirm.to_json}, danger: true});
                    } else {
                        accept();
                    }
                });
                $('.bu-reject-invitation').on('click', function(e) {
                    let other_email = $(e.currentTarget).data('email');
                    api_call('/api/reject_#{key}_invitation', {sus_email: sus_email, other_email: other_email}, function(response) {
                        if (response.success) {
                            window.location.reload();
                        }
                    });
                });
            });
            </script>
        HTML
    end

    STUDENT_GROUPS.each_pair do |key, group|
        post "/api/send_invitation_for_#{key}" do
            data = parse_request_data(:required_keys => [:sus_email, :name])
            sus_email = data[:sus_email]
            assert_student_group_access!(group, sus_email)
            other_email = @@user_info.keys.find { |email| @@user_info[email][:display_name] == data[:name] }
            assert(other_email != nil)
            invite_into_student_group!(group, sus_email, other_email)
            respond(:yay => 'sure')
        end

        post "/api/delete_invitation_for_#{key}" do
            data = parse_request_data(:required_keys => [:sus_email, :other_email])
            sus_email = data[:sus_email]
            assert_student_group_access!(group, sus_email)
            assert(@@user_info.include?(data[:other_email]))
            withdraw_student_group_invitation!(group, sus_email, data[:other_email])
            respond(:yay => 'sure')
        end

        post "/api/pending_#{key}_invitations_outgoing" do
            data = parse_request_data(:required_keys => [:sus_email])
            assert_student_group_access!(group, data[:sus_email], check_student: false)
            respond(:html => pending_student_group_invitations_outgoing(group, data[:sus_email]))
        end

        post "/api/accept_#{key}_invitation" do
            data = parse_request_data(:required_keys => [:sus_email, :other_email])
            sus_email = data[:sus_email]
            assert_student_group_access!(group, sus_email)
            assert(@@user_info.include?(data[:other_email]))
            accept_student_group_invitation!(group, sus_email, data[:other_email])
            respond(:yay => 'sure')
        end

        post "/api/reject_#{key}_invitation" do
            data = parse_request_data(:required_keys => [:sus_email, :other_email])
            sus_email = data[:sus_email]
            assert_student_group_access!(group, sus_email)
            assert(@@user_info.include?(data[:other_email]))
            reject_student_group_invitation!(group, sus_email, data[:other_email])
            respond(:yay => 'sure')
        end
    end
end
