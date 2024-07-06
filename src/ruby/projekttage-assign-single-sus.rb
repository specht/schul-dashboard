#!/usr/bin/env ruby

SKIP_COLLECT_DATA = true
require './main.rb'
require './parser.rb'
require 'digest'
require 'set'
require 'yaml'

class Script
    include Neo4jBolt
    def initialize(user, projekt)
        @user = user.downcase
        @projekt = projekt.downcase
        @@user_info = YAML.load_file(
            "/internal/debug/@@user_info.yaml",
            permitted_classes: [Set, Symbol]
        )
    end

    def run()
        STDERR.print "Searching for user #{@user}: "
        rows = @@user_info.keys.select do |email|
            email.index(@user) == 0
        end
        assert(rows.length == 1, "User not found")
        user = rows[0]
        STDERR.puts "found user #{user}"

        STDERR.print "Searching for project #{@projekt}: "
        candidates = []
        $neo4j.neo4j_query("MATCH (p:Projekt) RETURN p;") do |row|
            projekt = row["p"]
            if projekt[:title].downcase.include?(@projekt)
                candidates << projekt
            end
        end
        assert(candidates.length == 1, "Project not found")
        projekt = candidates[0]
        STDERR.puts "found project #{projekt[:title]}"

        STDERR.puts "Removing assignment for #{user}..."
        neo4j_query("MATCH (u:User {email: $email})-[r:ASSIGNED_TO]->(p) DELETE r;", {email: user})
        STDERR.puts "Assigning #{user} to #{projekt[:title]}"
        neo4j_query("MATCH (u:User {email: $email}) MATCH (p:Projekt {nr: $nr}) CREATE (u)-[r:ASSIGNED_TO]->(p);", {email: user, nr: projekt[:nr]})
    end
end

script = Script.new(ARGV[0], ARGV[1])
script.run
