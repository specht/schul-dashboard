#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require './timetable.rb'
require 'json'
require 'zlib'
require 'fileutils'
require 'thread'

PING_TIME = DEVELOPMENT ? 1 : 60

class Neo4jGlobal
    include Neo4jBolt
end

$neo4j = Neo4jGlobal.new

class ImageBotRepl < Sinatra::Base
    configure do
        set :show_exceptions, false
    end

    def self.assign_projects(emails, users, projects,
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

    def self.update_projektwahl()
        @@user_info ||= YAML.load_file(
            "/internal/debug/@@user_info.yaml",
            permitted_classes: [Set, Symbol]
        )
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
        latest_vote_ts = 0
        $neo4j.neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (u:User)-[r:VOTED_FOR]->(p:Projekt)
            RETURN u.email, r.vote, r.ts_updated, p.nr;
        END_OF_QUERY
            email = row['u.email']
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
            }
            (p[:min_klasse]..p[:max_klasse]).each do |klassenstufe|
                projects_for_klassenstufe[klassenstufe] ||= Set.new()
                projects_for_klassenstufe[klassenstufe] << nr
            end
        end
        projects_for_email = {}
        count = 0
        1000.times do
            begin
                result = assign_projects(emails, users, projects,
                    projects_for_klassenstufe, total_capacity,
                    votes, votes_by_email,
                    votes_by_vote, votes_by_project)
                error_sum = result[:error_for_email].values.sum
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
                # raise
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
                    p = projects_for_email[email][nr].to_f * 100.0 / count
                    if users[email][:vote_hash].size == 1
                        p *= 0.33
                    elsif users[email][:vote_hash] == 2
                        p *= 0.66
                    end
                    p = p.round
                    p = 1 if p < 1
                    p = 99 if p > 99
                    probabilities[email][nr] = sprintf('%d%%', p)
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
                    }
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

    def self.perform_update()
        update_projektwahl()
        STDERR.puts ">>> Refreshing uploaded images!"
        file_count = 0
        start_time = Time.now
        # convert uploaded images
        paths = Dir['/raw/uploads/images/*'].sort
        paths.each do |path|
            tag = File.basename(path).split('.').first
            last_jpg_path = path
            (GEN_IMAGE_WIDTHS.reverse + [:p]).each do |width|
                jpg_path = File.join("/gen/i/#{tag}-#{width}.jpg")
                unless File.exist?(jpg_path)
                    STDERR.puts jpg_path
                    if width == :p
                        system("convert -auto-orient -set colorspace RGB  \"#{last_jpg_path}\" -blur 0x8 -quality 85 -sampling-factor 4:2:0 -strip \"#{jpg_path}\"")
                    else
                        system("convert -auto-orient -set colorspace RGB  \"#{last_jpg_path}\" -resize #{width}x\\> -quality 85 -sampling-factor 4:2:0 -strip \"#{jpg_path}\"")
                    end
                    file_count += 1
                end
                webp_path = File.join("/gen/i/#{tag}-#{width}.webp")
                unless File.exist?(webp_path)
                    STDERR.puts webp_path
                    system("cwebp -quiet \"#{jpg_path}\" -q #{webp_path.include?('-b') ? 100 : 85} -o \"#{webp_path}\"")
                    file_count += 1
                end
                last_jpg_path = jpg_path
            end
        end
        end_time = Time.now
        STDERR.puts sprintf("<<< Finished refreshing uploaded images in %1.2f seconds, wrote #{file_count} files.", (end_time - start_time).to_f)
        STDERR.puts '-' * 59

        STDERR.puts ">>> Refreshing background images!"
        file_count = 0
        start_time = Time.now
        # convert background images
        paths = Dir['/gen/bg/*.svg'].sort
        paths.each do |svg_path|
            tag = File.basename(svg_path).split('.').first
            png_path = "/gen/bg/#{tag}.png"
            jpg_path = "/gen/bg/#{tag}.jpg"
            jpg_512_path = "/gen/bg/#{tag}-512.jpg"
            unless File.exist?(png_path)
                STDERR.puts "Creating #{png_path}..."
                system("inkscape --export-filename=#{png_path} #{svg_path}")
                file_count += 1
            end
            unless File.exist?(jpg_path)
                STDERR.puts "Creating #{jpg_path}..."
                system("convert #{png_path} #{jpg_path}")
                file_count += 1
            end
            unless File.exist?(jpg_512_path)
                STDERR.puts "Creating #{jpg_512_path}..."
                system("convert #{jpg_path} -resize 512x #{jpg_512_path}")
                file_count += 1
            end
        end
        end_time = Time.now
        STDERR.puts sprintf("<<< Finished refreshing background images in %1.2f seconds, wrote #{file_count} files.", (end_time - start_time).to_f)
        STDERR.puts '-' * 59
    end

    configure do
        begin
            if @@worker_thread
                Thread.kill(@@worker_thread)
            end
        rescue
        end
        @@queue = Queue.new
        @@queue << {:which => 'all'}
        @@worker_thread = Thread.new do
            future_queue = {}
            while true do
                entry = @@queue.pop
                if entry[:ping]
                    now = Time.now.to_i
                    keys = future_queue.keys
                    keys.each do |which|
                        if now - future_queue[which] > DELAYED_UPDATE_TIME
                            self.perform_update(which)
                            future_queue.delete(which)
                        end
                    end
                else
                    self.perform_update()
                end
            end
        end
        @@ping_thread = Thread.new do
            while true do
                @@queue << {:ping => true}
                sleep PING_TIME
            end
        end
        STDERR.puts "REPL is ready."
    end

    get '/api/update_all' do
        @@queue << {:which => :all}
    end

    run! if app_file == $0
end
