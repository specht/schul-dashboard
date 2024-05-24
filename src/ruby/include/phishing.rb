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

        if running_pishing_training? || developer_logged_in?
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
end