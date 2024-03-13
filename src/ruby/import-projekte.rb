#!/usr/bin/env ruby

require 'date'
require 'neo4j_bolt'
require 'set'
require 'xsv'
require 'yaml'

include Neo4jBolt

Neo4jBolt.bolt_host = 'neo4j'
Neo4jBolt.bolt_port = 7687

SRSLY = ARGV.include?('--srsly')

unless SRSLY
    puts "Not doing anything, specify --srsly to actually import data."
end

user_info = YAML.load_file("/internal/debug/@@user_info.yaml")
shorthands = YAML.load_file("/internal/debug/@@shorthands.yaml")

def gen_reverse_index(users, key)
    index = {}
    users.each_pair do |email, user|
        value = user[key].split('-').first
        if value
            value = value.downcase.strip
            index[value] ||= Set.new()
            index[value] << email
        end
    end
    index
end

last_name_to_email = gen_reverse_index(user_info, :last_name)
first_name_to_email = gen_reverse_index(user_info, :first_name)

def find_email_for_name(first_name, last_name, first_name_to_email, last_name_to_email)
    a = first_name_to_email[first_name.split('-').first.downcase.strip] || Set.new()
    b = last_name_to_email[last_name.split('-').first.downcase.strip] || Set.new()
    c = a & b
    if c.empty?
        STDERR.puts a.to_a.to_yaml
        STDERR.puts b.to_a.to_yaml
        raise "No email found for #{first_name} #{last_name}!"
    end
    if c.size > 1
        raise "Multiple emails found for #{first_name} #{last_name}!"
    end
    return c.to_a.first
end


this_year = Date.today.year
workbook = Xsv.open("/data/projekte/projekte-#{this_year}.xlsx", parse_headers: true)

if SRSLY
    STDERR.puts "Deleting old project nodes..."
    neo4j_query("MATCH (p:Projekt) DETACH DELETE p;")
end

sheet = workbook.first
sheet.each do |row|
    # STDERR.puts row.to_yaml
    break if row['Vorname'].nil?
    email = find_email_for_name(row['Vorname'], row['Nachname'], first_name_to_email, last_name_to_email)
    title = row['Titel']
    lehrer = [row['Koll 1'], row['Koll 2']].join('/').split('/').reject { |x| (x || '').strip.empty? }.map { |x| shorthands[x.strip] }.reject { |x| x.nil? }
    cats = (row['Kategorie'] || '').split('/').map { |x| x.strip }.reject { |x| x.empty? }
    nr = (row['Nr'] || '').to_s.strip.gsub(/\s/, '').strip
    jahrgang = (row['Jahrgang'] || '').strip.downcase
    min_klasse = 5
    max_klasse = 9
    if jahrgang.include?('nur')
        min_klasse = jahrgang.gsub('nur', '').strip.to_i
        max_klasse = min_klasse
    elsif jahrgang.include?('-')
        min_klasse = jahrgang.split('-')[0].to_i
        max_klasse = jahrgang.split('-')[1].to_i
    end
    if nr.empty?
        nr = 'Dok'
        min_klasse = nil
        max_klasse = nil
    end
    STDERR.puts "E-Mail: #{email}"
    STDERR.puts "Titel: [#{nr}] #{title} (#{cats.join(', ')}) (Klassen #{min_klasse} bis #{max_klasse})"
    STDERR.puts "Lehrer: #{lehrer.join(', ')}"
    STDERR.puts '-' * 40
    data = {
        :title => title,
        :categories => cats,
        :nr => nr,
        :min_klasse => min_klasse,
        :max_klasse => max_klasse,
    }
    neo4j_query(<<~END_OF_QUERY, {:nr => data[:nr], :data => data})
        MERGE (p:Projekt {nr: $nr})
        SET p = $data;
    END_OF_QUERY
    lehrer.each do |email|
        neo4j_query(<<~END_OF_QUERY, {:nr => data[:nr], :email => email})
            MATCH (p:Projekt {nr: $nr})
            MATCH (u:User {email: $email})
            CREATE (p)-[:SUPERVISED_BY]->(u);
        END_OF_QUERY
    end
    neo4j_query(<<~END_OF_QUERY, {:nr => data[:nr], :email => email})
        MATCH (p:Projekt {nr: $nr})
        MATCH (u:User {email: $email})
        CREATE (p)-[:ORGANIZED_BY]->(u);
    END_OF_QUERY
end

