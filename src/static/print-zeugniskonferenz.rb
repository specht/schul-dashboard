#!/usr/bin/env ruby

require 'date'
require 'json'
require 'yaml'
require './fragments.rb'

KLASSEN_ORDER = ['5a', '5b', '5c', '6a', '6b', '6c', '7a', '7b', '7c', '7e', '8a', '8b', '8c', '8d', '8e', '9a', '9b', '9c', '9e', '10a', '10b', '10o']
require '/data/zeugnisse/config.rb'

class Main
    def self.tr_klasse(klasse)
        {'10o' => '10ω'}[klasse] || klasse
    end
end

class Main
    def initialize
        cache = JSON.parse(File.read('/internal/zeugniskonferenz_cache.json'))
        @@zeugnisliste_for_klasse = YAML::load(File.read('/internal/debug/@@zeugnisliste_for_klasse.yaml'))
        @@shorthands = YAML::load(File.read('/internal/debug/@@shorthands.yaml'))
        @@user_info = YAML::load(File.read('/internal/debug/@@user_info.yaml'))
        @@klassenleiter = YAML::load(File.read('/internal/debug/@@klassenleiter.yaml'))

        File.open('/internal/out.pdf', 'w') do |f|
            # f.write get_zeugnislisten_sheets_pdf(cache)
            # f.write get_zeugniskonferenz_sheets_pdf(cache)
            f.write get_sozialzeugnis_pdf('10o', cache)
        end
    end
end

Main.new
