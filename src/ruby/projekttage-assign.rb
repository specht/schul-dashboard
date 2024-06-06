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

    def assign_projects(emails, users, projects,
        projects_for_klassenstufe, total_capacity,
        votes, _votes_by_email,
        _votes_by_vote, _votes_by_project)
        votes_by_email = Hash[_votes_by_email.map { |a, b| [a, b.dup ] } ]
        votes_by_vote = Hash[_votes_by_vote.map { |a, b| [a, b.dup ] } ]
        votes_by_project = Hash[_votes_by_project.map { |a, b| [a, b.dup ] } ]
        # STDERR.puts "Got #{emails.size} emails"
        # STDERR.puts "Got #{projects.size} projects with a total capacity of #{total_capacity}"
        # STDERR.puts "Total capacity: #{total_capacity}"
        # STDERR.puts "Schueler: #{emails.size}"
        result = {
            :project_for_email => {},
            :error_for_email => {},
            :emails_for_project => Hash[projects.map { |k, v| [k, []] } ],
        }
        # STDERR.puts result.to_yaml
        current_vote = 3
        remaining_emails = Set.new(emails)
        # STEP 1: Assign projects by priority
        loop do
            votes_by_vote[current_vote] ||= Set.new()
            while votes_by_vote[current_vote].empty?
                current_vote -= 1
                if current_vote == 0
                    break
                end
            end
            if current_vote == 0
                break
            end
            sha1 = votes_by_vote[current_vote].to_a.sample
            vote = votes[sha1]
            nr = vote[:nr]
            email = vote[:email]
            # STDERR.puts "[#{current_vote} / #{votes_by_vote[current_vote].size} left] #{sha1} => #{vote.to_json}"
            if result[:emails_for_project][nr].size < projects[nr][:capacity]
                # user can be assigned to project
                result[:emails_for_project][nr] << email
                if result[:project_for_email][email]
                    raise 'argh'
                end
                remaining_emails.delete(email)
                result[:project_for_email][email] = nr
                result[:error_for_email][email] = users[email][:highest_vote] - current_vote
                # clear all entries of user
                votes_by_email[email].each do |x|
                    votes_by_vote[votes[x][:vote]].delete(x)
                end
            end
            votes_by_vote[current_vote].delete(sha1)
        end
        # STDERR.puts "Assigned #{result[:project_for_email].size} of #{emails.size} users."
        # STEP 2: Randomly assign the rest
        remaining_projects = Set.new()
        projects.each_pair do |nr, p|
            if p[:capacity] - result[:emails_for_project][nr].size > 0
                remaining_projects << nr
            end
        end
        while !remaining_emails.empty?
            email = remaining_emails.to_a.sample
            klassenstufe = @@user_info[email][:klassenstufe] || 7
            pool = projects_for_klassenstufe[klassenstufe] & remaining_projects
            if pool.empty?
                raise 'oops'
            end
            nr = pool.to_a.sample
            remaining_emails.delete(email)
            if result[:project_for_email][email]
                raise 'argh'
            end
            result[:project_for_email][email] = nr
            result[:emails_for_project][nr] << email
            result[:error_for_email][email] = users[email][:highest_vote] || 0
            if result[:emails_for_project][nr].size >= projects[nr][:capacity]
                remaining_projects.delete(nr)
            end
        end
        # STDERR.puts "Assigned #{result[:project_for_email].size} of #{emails.size} users."
        result
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
            MATCH (u:User)-[r:VOTED_FOR]->(p:Projekt)
            RETURN u.email, r.vote, p.nr;
        END_OF_QUERY
            email = row['u.email']
            vote = row['r.vote']
            nr = row['p.nr']
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
            MATCH (p:Projekt) RETURN p;
        END_OF_QUERY
            p = row['p']
            next if (p[:capacity] || 0) == 0
            projects[p[:nr]] = {
                :nr => p[:nr],
                :title => p[:title],
                :capacity => p[:capacity],
                :min_klasse => p[:min_klasse],
                :max_klasse => p[:max_klasse],
                :participants => [],
            }
        end
        total_capacity = 0
        projects.each do |nr, p|
            total_capacity += p[:capacity]
        end
        projects_for_klassenstufe = {}
        projects.each do |nr, p|
            (p[:min_klasse]..p[:max_klasse]).each do |klassenstufe|
                projects_for_klassenstufe[klassenstufe] ||= Set.new()
                projects_for_klassenstufe[klassenstufe] << nr
            end
        end
        projects_for_email = {}
        sum = 0
        1000.times do
            begin
                result = assign_projects(emails, users, projects,
                    projects_for_klassenstufe, total_capacity,
                    votes, votes_by_email,
                    votes_by_vote, votes_by_project)
                error_sum = result[:error_for_email].values.sum
                sum += 1
                # STDERR.puts "Error: #{error_sum}"
                result[:project_for_email].each_pair do |email, project|
                    projects_for_email[email] ||= {}
                    projects_for_email[email][project] ||= 0
                    projects_for_email[email][project] += 1
                end
            rescue StandardError => e
            end
        end
        probabilities = {}
        emails.each do |email|
            probabilities[email] = {}
            users[email][:vote_hash].keys.each do |x|
                probabilities[email][x[0]] = '0%'
            end
        end
        projects_for_email.each_pair do |email, probs|
            projects_for_email[email].keys.each do |nr|
                if users[email][:vote_hash].include?(nr)
                    probabilities[email][nr] = sprintf('%d%%', (projects_for_email[email][nr].to_f * 100.0 / sum).round)
                end
            end
        end
        # STDERR.puts probabilities['linus.ziebart@mail.gymnasiumsteglitz.de'].to_yaml
        FileUtils::mkpath('/internal/projekttage/votes')
        probabilities.each_pair do |email, probs|
            File.open("/internal/projekttage/votes/#{email}.json", 'w') do |f|
                f.write probs.to_json
            end
        end
    end
end

script = Script.new
script.run
