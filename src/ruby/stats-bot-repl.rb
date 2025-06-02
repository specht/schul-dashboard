#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require './timetable.rb'
require 'json'
require 'zlib'
require 'fileutils'
require 'thread'

class Neo4jGlobal
    include Neo4jBolt
end

$neo4j = Neo4jGlobal.new

class StatsBotRepl < Sinatra::Base
    configure do
        set :show_exceptions, false
    end

    def self.update_projektwahl()
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
        (1..3).each do |i|
            votes_by_vote[i] ||= Set.new()
        end
        votes_by_email = {}
        votes_by_project = {}
        latest_vote_ts = 0
        $neo4j.neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (u:User)-[r:VOTED_FOR]->(p:Projekttage)
            RETURN u.email, r.vote, r.ts_updated, p.nr;
        END_OF_QUERY
            email = row['u.email']
            next unless users[email]
            vote = row['r.vote']
            nr = row['p.nr']
            latest_vote_ts = row['r.ts_updated'] if row['r.ts_updated'] > latest_vote_ts
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

        stored_vote_ts = nil
        begin
            stored_vote_ts = JSON.parse(File.read('/internal/projekttage/votes/ts.json'))['ts']
        rescue
        end

        STDERR.puts "stored_vote_ts: #{stored_vote_ts}, latest_vote_ts: #{latest_vote_ts}"
        if stored_vote_ts
            if (stored_vote_ts >= latest_vote_ts) && (Time.now.to_i - stored_vote_ts < 10)
                STDERR.puts "Doing nothing, already up-to-date."
                return
            end
        end

        users.keys.each do |email|
            users[email][:votes] = users[email][:votes].sort do |a, b|
                b[1] <=> a[1]
            end
        end
        projects = {}
        $neo4j.neo4j_query(<<~END_OF_QUERY).each do |row|
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
        STDERR.puts "HEY! #{projects.size} projects found."
        total_capacity = 0
        projects.each do |nr, p|
            total_capacity += p[:teilnehmer_max]
        end
        projects_for_klassenstufe = {}
        project_stats = {}
        projects.each do |nr, p|
            project_stats[nr] = {
                :geschlecht_m => 0,
                :geschlecht_w => 0,
                :klasse => {
                    5 => 0,
                    6 => 0,
                    7 => 0,
                    8 => 0,
                    9 => 0,
                },
                :vote => {
                    0 => 0,
                    1 => 0,
                    2 => 0,
                    3 => 0
                },
                :sus => [],
            }
            (p[:klassenstufe_min]..p[:klassenstufe_max]).each do |klassenstufe|
                projects_for_klassenstufe[klassenstufe] ||= Set.new()
                projects_for_klassenstufe[klassenstufe] << nr
            end
        end
        projects_for_email = {}
        count = 0
        errors = [0, 0, 0, 0]
        1000.times do
            begin
                result = Main.assign_projects(emails, users, projects,
                    projects_for_klassenstufe, total_capacity,
                    votes, votes_by_email,
                    votes_by_vote, votes_by_project, @@user_info)
                error_sum = result[:error_for_email].values.sum
                result[:error_for_email].values.each do |e|
                    errors[e] += 1
                end
                count += 1
                # STDERR.puts "Error: #{error_sum}"
                result[:project_for_email].each_pair do |email, project|
                    projects_for_email[email] ||= {}
                    projects_for_email[email][project] ||= 0
                    projects_for_email[email][project] += 1
                end

                result[:emails_for_project].each_pair do |nr, emails|
                    emails.each do |email|
                        if @@user_info[email][:geschlecht] == 'm'
                            project_stats[nr][:geschlecht_m] += 1
                        else
                            project_stats[nr][:geschlecht_w] += 1
                        end
                        project_stats[nr][:klasse][@@user_info[email][:klassenstufe] || 7] += 1
                        project_stats[nr][:vote][users[email][:vote_hash][nr] || 0] += 1
                    end
                end
            rescue StandardError => e
                STDERR.puts "Ignoring: #{e}"
                # raise
            end
        end
        if count == 0
            STDERR.puts "Error: Couldn't distribute projects, aborting."
            projects_for_klassenstufe.keys.sort.each do |klassenstufe|
                count = projects_for_klassenstufe[klassenstufe].inject(0) { |sum, nr| sum + projects[nr][:teilnehmer_max] }
                STDERR.puts "Klassenstufe #{klassenstufe}: #{count} spots"
                projects_for_klassenstufe[klassenstufe].each do |nr|
                    STDERR.puts "  #{nr}: #{projects[nr][:name]} (#{projects[nr][:teilnehmer_max]})"
                end
            end
            return
        end
        STDERR.puts "count: #{count}"
        STDERR.puts "emails: #{emails.size}"
        errors.map! { |x| x.to_f / count / emails.size }
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
                    p = projects_for_email[email][nr].to_f * 100.0 / count
                    if users[email][:vote_hash].size == 1
                        p *= 0.33
                    elsif users[email][:vote_hash].size == 2
                        p *= 0.66
                    end
                    p = p.round
                    p = 1 if p < 1
                    p = 99 if p > 99
                    probabilities[email][nr] = sprintf('%d%%', p)
                    if users[email][:vote_hash][nr] > 0
                        project_stats[nr][:sus] << {
                            :email => email,
                            :prob => p,
                            :vote => users[email][:vote_hash][nr] || 0,
                        }
                    end
                end
            end
        end
        FileUtils::mkpath('/internal/projekttage/votes')
        probabilities.each_pair do |email, probs|
            File.open("/internal/projekttage/votes/#{email}.json", 'w') do |f|
                f.write probs.to_json
            end
        end
        File.open("/internal/projekttage/votes/ts.json", 'w') do |f|
            f.write({
                :ts => latest_vote_ts,
                :email_count_voted => votes_by_email.size,
                :email_count_total => emails.size,
                :total_capacity => total_capacity,
                :errors => errors,
            }.to_json)
        end
        projects.keys.each do |nr|
            File.open("/internal/projekttage/votes/project-#{nr}.json", 'w') do |f|
                stats = {
                    :geschlecht_m => (project_stats[nr][:geschlecht_m].to_f / count).round,
                    :geschlecht_w => (project_stats[nr][:geschlecht_w].to_f / count).round,
                    :klasse => {
                        5 => (project_stats[nr][:klasse][5].to_f / count).round,
                        6 => (project_stats[nr][:klasse][6].to_f / count).round,
                        7 => (project_stats[nr][:klasse][7].to_f / count).round,
                        8 => (project_stats[nr][:klasse][8].to_f / count).round,
                        9 => (project_stats[nr][:klasse][9].to_f / count).round,
                    },
                    :vote => {
                        0 => (project_stats[nr][:vote][0].to_f / count).round,
                        1 => (project_stats[nr][:vote][1].to_f / count).round,
                        2 => (project_stats[nr][:vote][2].to_f / count).round,
                        3 => (project_stats[nr][:vote][3].to_f / count).round,
                    },
                    :sus => project_stats[nr][:sus].sort do |a, b|
                        b[:prob] <=> a[:prob]
                    end,
                }
                f.write(stats.to_json)
            end
        end
        File.open("/internal/projekttage/votes/projects.json", 'w') do |f|
            info = {}
            votes_by_project.each_pair do |nr, votes|
                info[nr] = {
                    :vote_count => votes.size,
                }
            end
            f.write info.to_json
        end
    end

    def self.perform_update(which)
        start_time = Time.now
        STDERR.puts ">>> Refreshing stats!"
        if which == :projektwahl || which == :all
            update_projektwahl()
        end
        end_time = Time.now
        STDERR.puts sprintf("<<< Finished refreshing stats in %1.2f seconds.", (end_time - start_time).to_f)
        STDERR.puts '-' * 59
    end

    configure do
        @@user_info = Main.class_variable_get(:@@user_info)
        begin
            if @@worker_thread
                Thread.kill(@@worker_thread)
            end
        rescue
        end
        @@queue = Queue.new
        @@queue << {:which => :all}
        @@worker_thread = Thread.new do
            while true do
                entry = @@queue.pop
                self.perform_update(entry[:which])
            end
        end
        STDERR.puts "REPL is ready."
    end

    get '/api/update/*' do
        data = request.env['REQUEST_PATH'].sub('/api/update/', '')
        if data == 'all'
            @@queue << {:which => :all}
        elsif data == 'projektwahl'
            @@queue << {:which => :projektwahl}
        end
    end

    run! if app_file == $0
end
