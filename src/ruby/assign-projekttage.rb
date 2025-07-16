#!/usr/bin/env ruby

require 'date'
require 'neo4j_bolt'
require 'set'
require 'yaml'

include Neo4jBolt

Neo4jBolt.bolt_host = 'neo4j'
Neo4jBolt.bolt_port = 7687

user_info = YAML.load_file("/internal/debug/@@user_info.yaml", permitted_classes: [Symbol, Set])

if ARGV.size < 2
    STDERR.puts "Usage: ./assign-projekttage.rb <user> <nr> --srsly"
    exit
end

candidates = user_info.keys.select do |email|
    email.include?(ARGV[0])
end

if candidates.size != 1
    STDERR.puts "Found #{candidates.size} candidates:"
    STDERR.puts candidates.to_yaml
    exit
end

email = candidates.first
srsly = ARGV[2] == '--srsly'
nr = ARGV[1]

projekt = neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => nr})['p']
    MATCH (p:Projekttage {nr: $nr})
    RETURN p;
END_OF_QUERY

puts "Assigning #{user_info[email][:display_name]} to #{projekt[:name]}..."

if srsly
    neo4j_query(<<~END_OF_QUERY, {:nr => nr, :email => email})
        MATCH (u:User {email: $email})-[r:ASSIGNED_TO]->(:Projekttage),
        (p:Projekttage {nr: $nr})
        DELETE r
        CREATE (u)-[:ASSIGNED_TO]->(p);
    END_OF_QUERY
else
    puts "Not doing anything unless you specify --srsly!"
end