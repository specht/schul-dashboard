class Main < Sinatra::Base
    def print_phishing_mail
        require_user!
        us =
        "<div class='text-comment'>
        <div class='from'>
            <h4><mark title='Rechtschreibfehler'>Dein</mark> E-Mail-Adresse wurde für eine Löschung markiert</h4>
            <p>
                <b>Dashboard Gymnasium Steglitz</b> &lt;noreply@<mark title='Keine offizielle Schul-Domain'>steglitzdashboard.de</mark>&gt;<br>
                <b>Via</b> '<mark title='Keine offizielle Schul-Domain'>steglitzdashboard.de</mark>'<br>
                <b>An</b> #{@session_user[:email]}<br>
            </p>
            <p>
                <button class='btn btn-outline-primary'>Antworten</button>
                <button class='btn btn-outline-primary'>Allen antworten</button>
                <button class='btn btn-outline-success'>Weiterleiten</button>
                <button class='btn btn-outline-danger'>Löschen</button>
            </p>
        </div>
        <div class='message'>
            <p>Hallo!</p>
            <p>Da Deine E-Mail-Adresse in der Datenbank nicht mehr vorkommt, wurde <mark title='Rechtschreibfehler'>es</mark> für eine <b>Löschung</b> markiert.</p>
            <p><mark title='Drohung' class='threat'>Bitte melde <mark title='Rechtschreibfehler'>dich sich</mark> über diesen <a href='phishing'>Link</a> im Dashboard an, wenn du den Vorgang abbrechen möchtest.</mark></p>
            <p>Der Link ist personalisiert und enthält persönliche Infos, gib diesen Link auf keinen Fall weiter.</p>
            <p>Wenn du alle Schritte richtig gemacht hast leuchtet dieser <mark title='Rechtschreibfehler'>Hacken</mark> grün auf: ☑️</p>
        </div>
        </div>"
        ms1 =
        "<div class='text-comment'>
                    <div class='from'>
                        <h4>Deine E-Mail-Adresse wurde für eine Löschung markiert</h4>
                        <p>
                            <b>Dashboard Gymnasium Steglitz</b> &lt;noreply@<mark title='Keine offizielle Schul-Domain'>steglitzdashboard.de</mark>&gt;<br>
                            <b>Via</b> '<mark title='Keine offizielle Schul-Domain'>steglitzdashboard.de</mark>'<br>
                            <b>An</b> #{@session_user[:email]}<br>
                        </p>
                        <p>
                            <button class='btn btn-outline-primary'>Antworten</button>
                            <button class='btn btn-outline-primary'>Allen antworten</button>
                            <button class='btn btn-outline-success'>Weiterleiten</button>
                            <button class='btn btn-outline-danger'>Löschen</button>
                        </p>
                    </div>
                    <div class='message'>
                        <p>Hallo!</p>
                        <p>Da Deine E-Mail-Adresse in der Datenbank nicht mehr vorkommt, wurde sie für eine <b>Löschung</b> markiert.</p>
                        <p><mark title='Drohung' class='threat'>Bitte melde <mark title='Rechtschreibfehler'>dich sich</mark> über diesen <a href='phishing'>Link</a> im Dashboard an, wenn du den Vorgang abbrechen möchtest.</mark></p>
                        <p>Der Link ist personalisiert und enthält persönliche Infos, gib diesen Link auf keinen Fall weiter.</p>
                        <p>Viele Grüße,<br>Dashboard Gymnasium Steglitz</p>
                    </div>
                    </div>"
        ms2 =
        "<div class='text-comment'>
                    <div class='from'>
                        <h4>Deine E-Mail-Adresse wurde für eine Löschung markiert</h4>
                        <p>
                            <b>Dashboard Gymnasium Steglitz</b> &lt;noreply@<mark title='Keine offizielle Schul-Domain'>steglitzdashboard.de</mark>&gt;<br>
                            <b>Via</b> '<mark title='Keine offizielle Schul-Domain'>steglitzdashboard.de</mark>'<br>
                            <b>An</b> #{@session_user[:email]}<br>
                        </p>
                        <p>
                            <button class='btn btn-outline-primary'>Antworten</button>
                            <button class='btn btn-outline-primary'>Allen antworten</button>
                            <button class='btn btn-outline-success'>Weiterleiten</button>
                            <button class='btn btn-outline-danger'>Löschen</button>
                        </p>
                    </div>
                    <div class='message'>
                        <p>Hallo!</p>
                        <p>Da Deine E-Mail-Adresse in der Datenbank nicht mehr vorkommt, wurde sie für eine <b>Löschung</b> markiert.</p>
                        <p><mark title='Drohung' class='threat'>Bitte melde dich über diesen <a href='phishing'>Link</a> im Dashboard an, wenn du den Vorgang abbrechen möchtest.</mark></p>
                        <p>Der Link ist personalisiert und enthält persönliche Infos, gib diesen Link auf keinen Fall weiter.</p>
                        <p>Viele Grüße,<br>Dashboard Gymnasium Steglitz</p>
                    </div>
                    </div>"
        os =
        "<div class='text-comment'>
                    <div class='from'>
                        <h4>Deine E-Mail-Adresse wurde für eine Löschung markiert</h4>
                        <p>
                            <b>Dashboard Gymnasium Steglitz</b> &lt;noreply@<mark title='Keine offizielle Schul-Domain'>steglitzdashboard.de</mark>&gt;<br>
                            <b>Via</b> '<mark title='Keine offizielle Schul-Domain'>steglitzdashboard.de</mark>'<br>
                            <b>An</b> #{@session_user[:email]}<br>
                        </p>
                        <p>
                            <button class='btn btn-outline-primary'>Antworten</button>
                            <button class='btn btn-outline-primary'>Allen antworten</button>
                            <button class='btn btn-outline-success'>Weiterleiten</button>
                            <button class='btn btn-outline-danger'>Löschen</button>
                        </p>
                    </div>
                    <div class='message'>
                        <p>Hallo!</p>
                        <p>Da Deine E-Mail-Adresse in der Datenbank nicht mehr vorkommt, wurde sie für eine <b>Löschung</b> markiert.</p>
                        <p><mark title='Drohung' class='threat'>Bitte melde dich über diesen <a href='phishing'>Link</a> im Dashboard an, wenn du den Vorgang abbrechen möchtest.</mark></p>
                        <p>Der Link ist personalisiert und enthält persönliche Infos, gib diesen Link auf keinen Fall weiter.</p>
                        <p>Viele Grüße,<br>Dashboard Gymnasium Steglitz</p>
                    </div>
                    </div>"
        teacher =
        "<div class='text-comment'>
        <div class='from'>
            <h4>Ihre E-Mail-Adresse wurde für eine Löschung markiert</h4>
            <p>
                <b>Dashboard Gymnasium Steglitz</b> &lt;noreply@<mark title='Keine offizielle Schul-Domain'>steglitzdashboard.de</mark>&gt;<br>
                <b>Via</b> '<mark title='Keine offizielle Schul-Domain'>steglitzdashboard.de</mark>'<br>
                <b>An</b> #{@session_user[:email]}<br>
            </p>
            <p>
                <button class='btn btn-outline-primary'>Antworten</button>
                <button class='btn btn-outline-primary'>Allen antworten</button>
                <button class='btn btn-outline-success'>Weiterleiten</button>
                <button class='btn btn-outline-danger'>Löschen</button>
            </p>
        </div>
        <div class='message'>
            <p>Hallo!</p>
            <p>Da Ihre E-Mail-Adresse in der Datenbank nicht mehr vorkommt, wurde sie für eine <b>Löschung</b> markiert.</p>
            <p><mark title='Drohung' class='threat'>Bitte melden Sie sich über diesen <a href='[link]'>Link</a> im Dashboard an, wenn Sie den Vorgang abbrechen möchten.</mark></p>
            <p>Der Link ist personalisiert und enthält persönliche Infos, geben Sie diesen Link auf keinen Fall weiter.</p>
            <p>Viele Grüße<br>Dashboard Gymnasium Steglitz</p>
        </div>
        </div>"

        if running_pishing_training? || user_with_role_logged_in?(:developer)
            return StringIO.open do |io|
                if [5, 6].include?(@session_user[:klassenstufe])
                    io.puts us
                elsif [7, 8].include?(@session_user[:klassenstufe])
                    io.puts ms1
                elsif [9, 10].include?(@session_user[:klassenstufe])
                    io.puts ms2
                elsif [11, 12].include?(@session_user[:klassenstufe])
                    io.puts os
                else
                    io.puts teacher
                end
                io.string
            end
        end
        return ''
    end

    def print_phishing_groups_table
        nutzerzahlen = {
          maennlich: {
            "5/6" => 0,
            "7/8" => 0,
            "9/10" => 0,
            "11/12" => 0,
            "Lehrkraft" => 0
          },
          weiblich: {
            "5/6" => 0,
            "7/8" => 0,
            "9/10" => 0,
            "11/12" => 0,
            "Lehrkraft" => 0
          }
        }

        @@user_info.each_value do |user|
            if user_has_role(user[:email], :teacher)
                if user[:geschlecht] == 'm'
                    nutzerzahlen[:maennlich]["Lehrkraft"] += 1
                elsif user[:geschlecht] == 'w'
                    nutzerzahlen[:weiblich]["Lehrkraft"] += 1
                end
            elsif user_has_role(user[:email], :schueler)
                gruppe = "#{user[:klassenstufe] <= 6 ? '5/6' : user[:klassenstufe] <= 8 ? '7/8' : user[:klassenstufe] <= 10 ? '9/10' : '11/12'}"
                if user[:geschlecht] == 'm'
                    nutzerzahlen[:maennlich][gruppe] += 1
                elsif user[:geschlecht] == 'w'
                    nutzerzahlen[:weiblich][gruppe] += 1
                end
            end
        end

        current_group = if teacher_logged_in?
                          "Lehrkraft"
                        else
                          "#{@session_user[:klassenstufe] <= 6 ? '5/6' : @session_user[:klassenstufe] <= 8 ? '7/8' : @session_user[:klassenstufe] <= 10 ? '9/10' : '11/12'}"
                        end
        current_gender = @session_user[:geschlecht] == 'm' ? :maennlich : :weiblich

        return StringIO.open do |io|
            io.puts "<p>
            Du warst für die Statistik in folgender der zehn Gruppen: <b>#{current_group}, #{current_gender == :maennlich ? 'männlich' : current_gender}</b>
            <div class='row'>
                <div class='col-md-12'>
                    <table class='table narrow'>
                    <thead>
                        <tr>
                            <th>Geschlecht</th>
                            <th>Klassenstufe</th>
                            <th></th>
                            <th></th>
                            <th></th>
                            <th></th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>männlich (#{nutzerzahlen[:maennlich]["Lehrkraft"]})</td>
                            <td class='#{'marked' if current_gender == :maennlich && current_group == '5/6'}'>5/6 (#{nutzerzahlen[:maennlich]["5/6"]})</td>
                            <td class='#{'marked' if current_gender == :maennlich && current_group == '7/8'}'>7/8 (#{nutzerzahlen[:maennlich]["7/8"]})</td>
                            <td class='#{'marked' if current_gender == :maennlich && current_group == '9/10'}'>9/10 (#{nutzerzahlen[:maennlich]["9/10"]})</td>
                            <td class='#{'marked' if current_gender == :maennlich && current_group == '11/12'}'>11/12 (#{nutzerzahlen[:maennlich]["11/12"]})</td>
                            <td class='#{'marked' if current_gender == :maennlich && current_group == 'Lehrkraft'}'>Lehrkraft (#{nutzerzahlen[:maennlich]["Lehrkraft"]})</td>
                        </tr>
                        <tr>
                            <td>weiblich (#{nutzerzahlen[:weiblich]["Lehrkraft"]})</td>
                            <td class='#{'marked' if current_gender == :weiblich && current_group == '5/6'}'>5/6 (#{nutzerzahlen[:weiblich]["5/6"]})</td>
                            <td class='#{'marked' if current_gender == :weiblich && current_group == '7/8'}'>7/8 (#{nutzerzahlen[:weiblich]["7/8"]})</td>
                            <td class='#{'marked' if current_gender == :weiblich && current_group == '9/10'}'>9/10 (#{nutzerzahlen[:weiblich]["9/10"]})</td>
                            <td class='#{'marked' if current_gender == :weiblich && current_group == '11/12'}'>11/12 (#{nutzerzahlen[:weiblich]["11/12"]})</td>
                            <td class='#{'marked' if current_gender == :weiblich && current_group == 'Lehrkraft'}'>Lehrkraft (#{nutzerzahlen[:weiblich]["Lehrkraft"]})</td>
                        </tr>
                    </tbody>
                    </table>
                </div>
            </div>
            </p>"
            io.string
            end
      end

end