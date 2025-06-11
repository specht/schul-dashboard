#!/usr/bin/env ruby

SKIP_COLLECT_DATA = true
require './main.rb'
require './parser.rb'
require 'digest'
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
        emails = @@user_info.keys.select do |email|
            if @@user_info[email][:roles].include?(:schueler)
                klassenstufe = @@user_info[email][:klassenstufe] || 7
                klassenstufe >= 5 && klassenstufe <= 9
            else
                false
            end
        end
        users = {}
        emails.each do |email|
            users[email] ||= {
                :votes => [],
                :vote_hash => {},
                :highest_vote => 0,
            }
        end
        votes = {}
        votes_by_vote = {}
        votes_by_email = {}
        votes_by_project = {}
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (u:User)-[r:VOTED_FOR]->(p:Projekttage)
            RETURN u.email, r.vote, p.nr;
        END_OF_QUERY
            email = row['u.email']
            vote = [row['r.vote'], 6].min
            nr = row['p.nr']
            next unless users[email]
            users[email][:votes] << [nr, vote]
            users[email][:vote_hash][nr] = vote
            users[email][:highest_vote] = vote if vote > users[email][:highest_vote]
            sha1 = Digest::SHA1.hexdigest("#{email}/#{vote}/#{nr}")[0, 12]
            votes[sha1] = {
                :email => email,
                :vote => vote,
                :nr => nr,
            }
            votes_by_vote[vote] ||= Set.new()
            votes_by_vote[vote] << sha1
            votes_by_email[email] ||= Set.new()
            votes_by_email[email] << sha1
            votes_by_project[nr] ||= Set.new()
            votes_by_project[nr] << sha1
        end

        users.keys.each do |email|
            users[email][:votes] = users[email][:votes].sort do |a, b|
                b[1] <=> a[1]
            end
        end
        projects = {}
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekttage) RETURN p;
        END_OF_QUERY
            p = row['p']
            next if (p[:teilnehmer_max] || 0) == 0
            projects[p[:nr]] = {
                :nr => p[:nr],
                :name => p[:name],
                :teilnehmer_max => p[:teilnehmer_max],
                :klassenstufe_min => p[:klassenstufe_min],
                :klassenstufe_max => p[:klassenstufe_max],
                :participants => [],
            }
        end
        total_capacity = 0
        projects.each do |nr, p|
            total_capacity += p[:teilnehmer_max]
        end
        projects_for_klassenstufe = {}
        projects.each do |nr, p|
            (p[:klassenstufe_min]..p[:klassenstufe_max]).each do |klassenstufe|
                projects_for_klassenstufe[klassenstufe] ||= Set.new()
                projects_for_klassenstufe[klassenstufe] << nr
            end
        end
        projects_for_email = {}
        sum = 0
        best_assignment = nil
        best_score = nil
        (DEVELOPMENT ? 100 : 10000).times do
            begin
                error_3_count = 0
                result = Main.assign_projects(emails, users, projects,
                    projects_for_klassenstufe, total_capacity,
                    votes, votes_by_email,
                    votes_by_vote, votes_by_project, @@user_info)
                error_sum = result[:error_for_email].values.sum
                result[:error_for_email].each_pair do |email, error|
                    error_3_count += 1 if error == 3
                end
                best_score ||= error_3_count
                best_assignment ||= result
                if error_3_count < best_score
                    best_score = error_3_count
                    best_assignment = result
                end
                sum += 1
                # STDERR.puts "Error: #{error_sum}"
                result[:project_for_email].each_pair do |email, project|
                    projects_for_email[email] ||= {}
                    projects_for_email[email][project] ||= 0
                    projects_for_email[email][project] += 1
                end
            rescue
                raise
            end
        end
        Main.print_project_assignment_summary_and_assign(best_assignment, @@user_info,
        votes, votes_by_email, votes_by_vote, votes_by_project)
    end
end

script = Script.new
script.run
STDERR.puts '>' * 40
STDERR.puts "Achtung: Bitte starte einmal den Ruby-Container neu, um die Mailinglisten zu aktualisieren."
STDERR.puts '>' * 40