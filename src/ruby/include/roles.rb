AVAILABLE_ROLES = {
    :teacher => 'Lehrkraft',
    :schueler => 'Schülerin / Schüler',
    :admin => 'Administrator',
    :developer => 'Entwickler',
    :sekretariat => 'Sekretariat',
    :zeugnis_admin => 'Zeugnis-Admin',
    :can_see_all_timetables => 'kann alle Stundenpläne sehen',
    # :can_manage_salzh,
    :can_upload_files => 'kann Dateien hochladen',
    :can_manage_news => 'kann News verwalten',
    :can_manage_monitors => 'kann Monitore verwalten',
    :can_manage_tablets => 'kann Tabletbuchungen verwalten',
    :can_use_aula => 'Aulatechnik',
    :can_manage_antikenfahrt => 'kann Antikenfahrt verwalten',
    :can_manage_agr_app => 'kann die Altgriechisch-App verwalten',
    :can_manage_bib => 'kann die Bibliothek verwalten',
    :can_manage_bib_members => 'kann Bibliotheksnutzer verwalten',
    :can_manage_bib_payment => 'kann Bibliothekszahlungen verwalten',
    :can_manage_bib_special_access => 'Bibliothek Spezialzugriff',
    :gev => 'GEV',
    :sv => 'Schülervertretung',
    :technikteam => 'Technikteam',
    :wants_to_receive_techpost_debug_mail => 'möchte E-Mails zu Technikproblemen erhalten',
    :datentresor_hotline => 'kann Lehrkräfte für den Datentresor freischalten',
    :schulbuchverein => 'Schulbuchverein',
    :can_receive_messages => 'kann Nachrichten empfangen',
    :can_write_messages => 'kann Nachrichten schreiben',
    :can_create_polls => 'kann Umfragen durchführen',
    :can_create_events => 'kann Termine anlegen',
    :can_use_mailing_lists => 'kann alle Mail-Verteiler verwenden',
    :can_use_nextcloud => 'kann die Nextcloud verwenden',
    :can_use_sms_gateway => 'kann die SMS-Anmeldung benutzen',
}

ROLE_TRANSITIONS = <<~END_OF_STRING
    teacher => can_receive_messages can_write_messages can_create_polls can_create_events can_use_mailing_lists can_use_nextcloud can_use_sms_gateway
    schueler => can_receive_messages can_use_nextcloud
    sv => can_write_messages can_create_polls can_use_mailing_lists can_create_events
    technikteam => can_write_messages can_create_polls can_use_mailing_lists can_create_events
    admin => can_upload_files can_manage_news can_manage_monitors can_manage_tablets
END_OF_STRING