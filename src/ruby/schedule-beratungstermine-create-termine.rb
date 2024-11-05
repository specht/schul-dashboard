#!/usr/bin/env ruby

require 'date'
require 'neo4j_bolt'
require 'set'
require 'xsv'
require 'time'
require 'yaml'
require 'securerandom'

include Neo4jBolt

CONSULTATION_DATE = '2024-11-12'
CONSULTATION_START_TIME = '14:45'
SLOT_DURATION = 5

Neo4jBolt.bolt_host = 'neo4j'
Neo4jBolt.bolt_port = 7687

SRSLY = ARGV.include?('--srsly')

unless SRSLY
    puts "Not doing anything, specify --srsly to actually import data."
end

user_info = YAML.load_file("/internal/debug/@@user_info.yaml", permitted_classes: [Symbol, Set])
shorthands = YAML.load_file("/internal/debug/@@shorthands.yaml")

class RandomTag
    BASE_31_ALPHABET = '0123456789bcdfghjklmnpqrstvwxyz'
    def self.to_base31(i)
        result = ''
        while i > 0
            result += BASE_31_ALPHABET[i % 31]
            i /= 31
        end
        result
    end

    def self.generate(length = 12)
        self.to_base31(SecureRandom.hex(length).to_i(16))[0, length]
    end
end

path = ARGV.first
raise 'Please specify the path to the output file of schedule-beratungstermine.yaml' if path.nil?
pk5_hash = YAML.load_file(path)

all_teachers = Set.new()
pk5_hash.each_pair do |tag, info|
    talks = (info[:talks] || {})
    talks.each_pair do |slot, teacher_email|
        all_teachers << teacher_email
    end
end

room_for_teacher = {}
path = '/data/pk5/rooms.csv'
if File.exist?(path)
    File.open(path) do |f|
        f.each_line do |line|
            line.strip!
            next if line[0] == '#'
            parts = line.split(',')
            shorthand = parts[0]
            room = parts[1]
            email = shorthands[shorthand]
            raise "Unknown shorthand #{shorthand} in path!" if email.nil?
            room_for_teacher[email] = room
        end
    end
end

shorthands_without_rooms = all_teachers.reject { |x| room_for_teacher[x] }.map { |x| user_info[x][:shorthand] }
unless shorthands_without_rooms.empty?
    puts '-' * 40
    shorthands_without_rooms.sort.each do |shorthand|
        puts "#{shorthand},"
    end
    puts '-' * 40
    raise "No rooms defined for #{shorthands_without_rooms.size} teachers!"
end

events = []

transaction do
    pk5_hash.each_pair do |tag, info|
        themengebiet = info[:pk5][:themengebiet]
        sus_emails = info[:emails]
        talks = (info[:talks] || {})
        # STDERR.puts "Warning: no talks scheduled for #{themengebiet}" if talks.empty?
        # STDERR.puts talks.to_yaml
        talks_for_teacher = talks.group_by { |a, b| b }
        talks_for_teacher.each_pair do |teacher_email, slots|
            timestamp = Time.now.to_i
            slots = slots.map { |a, b| a }
            slots.sort!
            event = {
                :id => RandomTag.generate(12),
                :created => timestamp,
                :updated => timestamp,
                :date => CONSULTATION_DATE,
                :start_time => (Time.parse("1970-01-01T#{CONSULTATION_START_TIME}") + slots.first * SLOT_DURATION * 60).strftime('%H:%M'),
                :end_time => (Time.parse("1970-01-01T#{CONSULTATION_START_TIME}") + (slots.last + 1) * SLOT_DURATION * 60).strftime('%H:%M'),
                :jitsi => false,
                :title => "Zentraler Beratungstermin #{user_info[teacher_email][:display_name_official]} / #{sus_emails.map { |x| user_info[x][:display_name]}.join(' / ')}",
                :description => "<p>#{themengebiet}</p><p>#{user_info[teacher_email][:display_name_official]}, #{sus_emails.map { |x| user_info[x][:display_name]}.join(', ')}</p>",
                :zentraler_beratungstermin => true,
            }
            events << { :event => event, :tag => tag, :teacher => teacher_email }
            # puts "#{event[:start_time]} - #{event[:end_time]} / #{event[:title]}"
            # if event[:end_time] > '16:15'
            #     puts "#{event[:start_time]} - #{event[:end_time]} / #{event[:title]}"
            # end
            if room_for_teacher[teacher_email]
                event[:description] += "<p>Raum #{room_for_teacher[teacher_email]}</p>"
            else
                # STDERR.puts "[WARNING] No room defined for teacher: #{teacher_email}"
            end
            if SRSLY
                node_id = neo4j_query_expect_one(<<~END_OF_QUERY, {:event => event, :teacher_email => teacher_email})['id']
                    MATCH (t:User {email: $teacher_email})
                    CREATE (e:Event)
                    SET e = $event
                    CREATE (e)-[:ORGANIZED_BY]->(t)
                    RETURN ID(e) AS id;
                END_OF_QUERY
                sus_emails.each do |sus_email|
                    neo4j_query_expect_one(<<~END_OF_QUERY, {:node_id => node_id, :sus_email => sus_email})
                        MATCH (e:Event)
                        WHERE ID(e) = $node_id
                        MATCH (u:User {email: $sus_email})
                        CREATE (u)-[:IS_PARTICIPANT]->(e)
                        RETURN e;
                    END_OF_QUERY
                end
                puts "Created event for #{teacher_email} / #{sus_emails.join(' / ')}"
            end
        end
    end
end

puts "Gesprächstermine für Lehrkräfte:"
puts
last_key = nil
events.sort do |a, b|
    a[:teacher] == b[:teacher] ?
    a[:event][:start_time] <=> b[:event][:start_time] :
    a[:teacher] <=> b[:teacher]
end.each do |x|
    last_key ||= x[:teacher]
    puts if last_key != x[:teacher]
    puts "#{x[:event][:start_time]} - #{x[:event][:end_time]} / #{x[:event][:title].sub('Zentraler Beratungstermin', '').strip} (#{x[:event][:description].match(/Raum ([^\)<]+)/)&.[](1)})"
    last_key = x[:teacher]
end

puts
puts "Gesprächstermine für SuS:"
puts
last_key = nil
events.sort do |a, b|
    a[:tag] == b[:tag] ?
    a[:event][:start_time] <=> b[:event][:start_time] :
    a[:tag] <=> b[:tag]
end.each do |x|
    last_key ||= x[:tag]
    puts if last_key != x[:tag]
    puts "#{x[:event][:start_time]} - #{x[:event][:end_time]} / #{x[:event][:title].sub('Zentraler Beratungstermin', '').strip} (#{x[:event][:description].match(/Raum ([^\)<]+)/)&.[](1)})"
    last_key = x[:tag]
end
