#!/usr/bin/env ruby
require 'fileutils'

(-3*12..3*12).each do |p|
    system("sox ../ruby/cypher/pitch/original.wav -r 44.1k -c 1 -b 16 ../ruby/cypher/pitch/pitch#{p >= 0 ? '+' : ''}#{p}.wav pitch #{p * 100}")
end
exit

['Alegreya-Sans-Bold', 'Alegreya-Sans-Regular'].each do |font|
    [24, 36, 72].each do |size|
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.each_char do |c|
            path = "../ruby/cypher/#{font}/#{size}/#{c}.png"
            FileUtils.mkpath(File.dirname(path))
            command = "convert -background 'transparent' -font '#{font}' -size 800x480 -trim +repage -fill '#ffffff' -pointsize #{size} -gravity center label:'#{c}' #{path}"
            system(command)
        end
    end
end