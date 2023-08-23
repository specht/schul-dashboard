#!/usr/bin/env ruby

require 'date'
require 'json'
require 'yaml'
require 'set'
require '../main.rb'
require './fragments.rb'

KLASSEN_ORDER = ['5a', '5b', '5c', '6a', '6b', '6c', '7a', '7b', '7c', '7e', '8a', '8b', '8c', '8d', '8e', '9a', '9b', '9c', '9e', '10a', '10b', '10o']
require '/data/zeugnisse/config.rb'

HOURS_FOR_KLASSE = {}

hd = '2022-08-22'
HOURS_FOR_KLASSE[hd] = {}
KLASSEN_ORDER.each do |klasse|
    klassenstufe = klasse.to_i
    HOURS_FOR_KLASSE[hd][klasse] = []
    if [5, 6].include?(klassenstufe)
        HOURS_FOR_KLASSE[hd][klasse] << ['07:30', '08:15']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:15', '09:00']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:05', '09:50']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:50', '10:30']
        HOURS_FOR_KLASSE[hd][klasse] << ['10:45', '11:30']
        HOURS_FOR_KLASSE[hd][klasse] << ['11:30', '12:10']
        HOURS_FOR_KLASSE[hd][klasse] << ['12:50', '13:35']
        HOURS_FOR_KLASSE[hd][klasse] << ['13:40', '14:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['14:30', '15:15']
        HOURS_FOR_KLASSE[hd][klasse] << ['15:20', '16:05']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:10', '16:55']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:55', '17:40']
    else
        HOURS_FOR_KLASSE[hd][klasse] << ['07:30', '08:15']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:15', '09:00']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:05', '09:50']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:50', '10:30']
        HOURS_FOR_KLASSE[hd][klasse] << ['10:45', '11:30']
        HOURS_FOR_KLASSE[hd][klasse] << ['11:30', '12:10']
        HOURS_FOR_KLASSE[hd][klasse] << ['12:20', '13:05']
        HOURS_FOR_KLASSE[hd][klasse] << ['13:40', '14:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['14:30', '15:15']
        HOURS_FOR_KLASSE[hd][klasse] << ['15:20', '16:05']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:10', '16:55']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:55', '17:40']
    end
end
hd = '2023-02-06'
HOURS_FOR_KLASSE[hd] = {}
KLASSEN_ORDER.each do |klasse|
    klassenstufe = klasse.to_i
    HOURS_FOR_KLASSE[hd][klasse] = []
    if [5, 6].include?(klassenstufe)
        HOURS_FOR_KLASSE[hd][klasse] << ['07:15', '08:00']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:00', '08:45']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:50', '09:35']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:35', '10:20']
        HOURS_FOR_KLASSE[hd][klasse] << ['10:40', '11:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['11:25', '12:10']
        HOURS_FOR_KLASSE[hd][klasse] << ['12:50', '13:35']
        HOURS_FOR_KLASSE[hd][klasse] << ['13:40', '14:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['14:30', '15:15']
        HOURS_FOR_KLASSE[hd][klasse] << ['15:20', '16:05']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:10', '16:55']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:55', '17:40']
    else
        HOURS_FOR_KLASSE[hd][klasse] << ['07:15', '08:00']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:00', '08:45']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:50', '09:35']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:35', '10:20']
        HOURS_FOR_KLASSE[hd][klasse] << ['10:40', '11:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['11:25', '12:10']
        HOURS_FOR_KLASSE[hd][klasse] << ['12:20', '13:05']
        HOURS_FOR_KLASSE[hd][klasse] << ['13:40', '14:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['14:30', '15:15']
        HOURS_FOR_KLASSE[hd][klasse] << ['15:20', '16:05']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:10', '16:55']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:55', '17:40']
    end
end
hd = '2023-07-03'
HOURS_FOR_KLASSE[hd] = {}
KLASSEN_ORDER.each do |klasse|
    klassenstufe = klasse.to_i
    HOURS_FOR_KLASSE[hd][klasse] = []
    if [5, 6].include?(klassenstufe)
        HOURS_FOR_KLASSE[hd][klasse] << ['07:30', '08:00']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:00', '08:30']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:35', '09:05']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:05', '09:35']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:55', '10:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['10:25', '10:55']
        HOURS_FOR_KLASSE[hd][klasse] << ['11:15', '11:45']
        HOURS_FOR_KLASSE[hd][klasse] << ['12:20', '12:50']
        HOURS_FOR_KLASSE[hd][klasse] << ['12:55', '13:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['13:30', '14:00']
        HOURS_FOR_KLASSE[hd][klasse] << ['14:05', '14:35']
        HOURS_FOR_KLASSE[hd][klasse] << ['14:40', '15:10']
    else
        HOURS_FOR_KLASSE[hd][klasse] << ['07:30', '08:00']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:00', '08:30']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:35', '09:05']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:05', '09:35']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:55', '10:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['10:25', '10:55']
        HOURS_FOR_KLASSE[hd][klasse] << ['11:15', '11:45']
        HOURS_FOR_KLASSE[hd][klasse] << ['11:50', '12:20']
        HOURS_FOR_KLASSE[hd][klasse] << ['12:55', '13:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['13:30', '14:00']
        HOURS_FOR_KLASSE[hd][klasse] << ['14:05', '14:35']
        HOURS_FOR_KLASSE[hd][klasse] << ['14:40', '15:10']
    end
end
hd = '2023-07-05'
HOURS_FOR_KLASSE[hd] = {}
KLASSEN_ORDER.each do |klasse|
    klassenstufe = klasse.to_i
    HOURS_FOR_KLASSE[hd][klasse] = []
    if [5, 6].include?(klassenstufe)
        HOURS_FOR_KLASSE[hd][klasse] << ['07:15', '08:00']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:00', '08:45']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:50', '09:35']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:35', '10:20']
        HOURS_FOR_KLASSE[hd][klasse] << ['10:40', '11:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['11:25', '12:10']
        HOURS_FOR_KLASSE[hd][klasse] << ['12:50', '13:35']
        HOURS_FOR_KLASSE[hd][klasse] << ['13:40', '14:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['14:30', '15:15']
        HOURS_FOR_KLASSE[hd][klasse] << ['15:20', '16:05']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:10', '16:55']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:55', '17:40']
    else
        HOURS_FOR_KLASSE[hd][klasse] << ['07:15', '08:00']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:00', '08:45']
        HOURS_FOR_KLASSE[hd][klasse] << ['08:50', '09:35']
        HOURS_FOR_KLASSE[hd][klasse] << ['09:35', '10:20']
        HOURS_FOR_KLASSE[hd][klasse] << ['10:40', '11:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['11:25', '12:10']
        HOURS_FOR_KLASSE[hd][klasse] << ['12:20', '13:05']
        HOURS_FOR_KLASSE[hd][klasse] << ['13:40', '14:25']
        HOURS_FOR_KLASSE[hd][klasse] << ['14:30', '15:15']
        HOURS_FOR_KLASSE[hd][klasse] << ['15:20', '16:05']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:10', '16:55']
        HOURS_FOR_KLASSE[hd][klasse] << ['16:55', '17:40']
    end
end

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
        @@faecher = YAML::unsafe_load(File.read('/internal/debug/@@faecher.yaml'))
        @@lessons = YAML::unsafe_load(File.read('/internal/debug/@@lessons.yaml'))

        File.open("/internal/out.pdf", 'w') do |f|
            # f.write get_zeugnislisten_sheets_pdf(cache)
            # f.write get_zeugniskonferenz_sheets_pdf(cache)
            # f.write get_fehlzeiten_sheets_pdf(cache)
            f.write get_timetable_pdf('5a', pick_random_color_scheme())
        end
        # self.fix_stundenzeiten()

        # KLASSEN_ORDER.each do |klasse|
        #     next if klasse.to_i > 10
        #     # next if klasse != '9e'
        #     File.open("/internal/out-#{klasse}.pdf", 'w') do |f|
        #         # f.write get_zeugnislisten_sheets_pdf(cache)
        #         # f.write get_zeugniskonferenz_sheets_pdf(cache)
        #         # f.write get_sozialzeugnis_pdf('10a', cache)
        #         f.write get_timetable_pdf(klasse)
        #     end
        #     system("inkscape --pdf-poppler -o /internal/out-#{klasse}.png /internal/out-#{klasse}.pdf")
        # end
    end
end

Main.new
