#!/usr/bin/env ruby

SKIP_COLLECT_DATA = true
require './main.rb'
require './parser.rb'
require 'set'
require 'yaml'

class Script
    include Neo4jBolt
    def initialize()
        @@user_info = YAML.load_file(
            "/internal/debug/@@user_info.yaml",
            permitted_classes: [Set, Symbol]
        )
    end

    def run()
        STDERR.puts "yay"
        emails = @@user_info.keys.select do |email|
            if @@user_info[email][:roles].include?(:schueler)
                klassenstufe = @@user_info[email][:klassenstufe] || 7
                klassenstufe >= 5 && klassenstufe <= 9
            else
                false
            end
        end
        emails.shuffle!
        STDERR.puts "Got #{emails.size} emails"
        STDERR.puts emails.to_yaml
        users = {}
        emails.each do |email|
            users[email] ||= {
                :votes => [],
                :highest_vote => 0,
                :projekt => nil,
            }
        end
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (u:User)-[r:VOTED_FOR]->(p:Projekt)
            RETURN u.email, r.vote, p.nr;
        END_OF_QUERY
            email = row['u.email']
            vote = row['r.vote']
            nr = row['p.nr']
            users[email][:votes] << [nr, vote]
            users[email][:highest_vote] = vote if vote > users[email][:highest_vote]
        end
        users.keys.each do |email|
            users[email][:votes] = users[email][:votes].sort do |a, b|
                b[1] <=> a[1]
            end
        end
        projekte = {}
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekt) RETURN p;
        END_OF_QUERY
            p = row['p']
            projekte[p[:nr]] = {
                :nr => p[:nr],
                :title => p[:title],
                :capacity => p[:capacity],
                :min_klasse => p[:min_klasse],
                :max_klasse => p[:max_klasse],
                :participants => [],
            }
        end
        emails.each do |email|
            klassenstufe = @@user_info[email][:klassenstufe] || 7
            # make sure there are at least 3 votes for each user
            while users[email][:votes].size < 3
                available_projects = Set.new(projekte.keys)
                available_projects.select! do |x|
                    klassenstufe >= projekte[x][:min_klasse] && klassenstufe <= projekte[x][:max_klasse]
                end
                users[email][:votes].each do |x|
                    available_projects.delete(x[0])
                end
                available_projects = available_projects.to_a
                users[email][:votes] << [available_projects.sample, 1]
            end
            users[email][:votes].shuffle!
            users[email][:votes] = users[email][:votes].sort do |a, b|
                b[1] <=> a[1]
            end
        end
    end
end

script = Script.new
script.run
