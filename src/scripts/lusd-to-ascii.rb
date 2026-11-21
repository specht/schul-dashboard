#!/usr/bin/env ruby
# Wandelt einen Schüler-Export aus der LUSD (CSV oder Excel) in
# schueler/ASCII.TXT um und vergleicht ihn mit der bisherigen Datei.
# Beschreibung: doc/Daten.md, Abschnitt »Schüler:innen«.

require 'optparse'
require_relative '../ruby/lusd_import'

options = { klassen: {} }
parser = OptionParser.new do |o|
    o.banner = "Aufruf: #{File.basename($0)} EXPORT [Optionen]\n\n" +
               "Ohne --aus wird nur geprüft und nichts geschrieben.\n\n"
    o.on('--vergleich DATEI', 'bisherige ASCII.TXT zum Vergleichen') { |v| options[:vergleich] = v }
    o.on('--klasse LUSD=DASHBOARD', 'Klassenname umschreiben (mehrfach möglich)') do |v|
        from, to = v.split('=', 2)
        abort "--klasse erwartet LUSD=DASHBOARD, z. B. --klasse Q1=12" if to.to_s.strip.empty?
        options[:klassen][from] = to.strip
    end
    o.on('--aus DATEI', 'neue ASCII.TXT hierhin schreiben') { |v| options[:aus] = v }
    o.on('--namen', 'Schüler:innen mit neuer E-Mail-Adresse namentlich auflisten') { options[:namen] = true }
end
parser.parse!
abort parser.help unless ARGV.size == 1

begin
    rows = LusdImport.read_rows(ARGV.first)
    result = LusdImport.convert(rows, options[:klassen])
    old = options[:vergleich] && LusdImport.read_current(options[:vergleich])
    puts LusdImport.report(result, old_students: old, show_names: options[:namen])
rescue LusdImport::Error, Errno::ENOENT => e
    abort "Fehler: #{e.message}"
end

exit 1 unless result[:errors].empty?
if options[:aus]
    tmp = "#{options[:aus]}.tmp"
    File.write(tmp, LusdImport.ascii_txt(result[:students]), encoding: 'UTF-8')
    File.rename(tmp, options[:aus])
    puts
    puts "Geschrieben: #{options[:aus]} (#{result[:students].size} Zeilen)"
end
