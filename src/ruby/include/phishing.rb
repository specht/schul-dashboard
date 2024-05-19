class Main < Sinatra::Base

    def print_phishing_mail
        require_user!
        start = PHISHING_HINT_START
        ende = PHISHING_HINT_END
        if Time.now.strftime('%Y-%m-%dT%H:%M:%S') >= start && Time.now.strftime('%Y-%m-%dT%H:%M:%S') <= ende
            return StringIO.open do |io|
                io.puts "<div class='text-comment'>
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
                io.string
            end
        end
        return ''
    end
end