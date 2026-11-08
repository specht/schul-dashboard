#!/usr/bin/env ruby
# Wandelt seats.js, rules.js und bff.js aus /data/sitzplan einmalig in die vom
# Dashboard verwalteten Dateien unter /internal/sitzplan um. Danach können die
# drei Dateien aus dem Datenrepo entfernt werden.
#
#   ruby migrate-sitzplan.rb           zeigt nur, was passieren würde
#   ruby migrate-sitzplan.rb --apply   schreibt die Dateien
#
# Bereits vorhandene Dateien unter /internal bleiben unangetastet (sie können neuer
# sein), das Skript darf also mehrfach laufen. Die Ausgabe nennt nur Anzahlen, keine
# Inhalte, weil rules und bff geheime Absprachen enthalten können. Schlägt eine
# Datei fehl, wird gar nichts geschrieben.

require './include/sitzplan_daten.rb'

apply = ARGV.include?('--apply')
errors = []

rooms = {}
begin
    rooms = SitzplanDaten.legacy_rooms
    rooms.each do |raum, seats|
        unless raum =~ SitzplanDaten::ROOM_NAME && SitzplanDaten.valid_seats?(seats)
            errors << "seats.js: Eintrag Nr. #{rooms.keys.index(raum) + 1} hat ein unerwartetes Format"
        end
    end
rescue SitzplanDaten::FormatError => e
    errors << "seats.js: #{e.message}"
end

lists = {}
SitzplanDaten::LISTS.each_key do |kind|
    begin
        entries = SitzplanDaten.legacy_list(kind)
        bad = entries.each_index.reject { |i| SitzplanDaten.valid_entry?(kind, entries[i]) }
        errors << "#{kind}: #{bad.size} Einträge haben ein unerwartetes Format" unless bad.empty?
        lists[kind] = entries
    rescue SitzplanDaten::FormatError => e
        errors << "#{kind}: #{e.message}"
    end
end

unless errors.empty?
    puts 'Nichts geschrieben, diese Dateien lassen sich nicht sicher umwandeln:'
    errors.each { |line| puts "  #{line}" }
    exit 1
end

new_rooms = rooms.keys.reject { |raum| File.exist?(SitzplanDaten.room_path(raum)) }
puts "Räume: #{rooms.size} gefunden, #{new_rooms.size} neu, #{rooms.size - new_rooms.size} schon vorhanden"
lists.each do |kind, entries|
    state = File.exist?(SitzplanDaten.list_path(kind)) ? 'schon vorhanden, bleibt' : 'neu'
    puts "#{kind}: #{entries.size} Einträge (#{state})"
end

unless apply
    puts 'Nur Vorschau. Zum Schreiben mit --apply aufrufen.'
    exit 0
end

FileUtils.mkdir_p(SitzplanDaten::ROOMS_DIR)
new_rooms.each { |raum| SitzplanDaten.write_atomic(SitzplanDaten.room_path(raum), rooms[raum]) }
lists.each do |kind, entries|
    path = SitzplanDaten.list_path(kind)
    SitzplanDaten.write_atomic(path, entries) unless File.exist?(path)
end
puts 'Fertig. seats.js, rules.js und bff.js können jetzt aus dem Datenrepo entfernt werden.'
