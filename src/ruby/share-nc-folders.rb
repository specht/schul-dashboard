#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'set'
require 'zlib'
require 'fileutils'
require 'nextcloud'
require 'cgi'
require 'yaml'

SHARE_READ = 1
SHARE_UPDATE = 2
SHARE_CREATE = 4
SHARE_DELETE = 8
SHARE_SHARE = 16

class Script
    def initialize
        @ocs = Nextcloud.ocs(url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER,
                             username: NEXTCLOUD_USER, 
                             password: NEXTCLOUD_PASSWORD)
    end
    
    def run
        @@user_info = Main.class_variable_get(:@@user_info)
        @@klassen_order = Main.class_variable_get(:@@klassen_order)
        @@lessons_for_klasse = Main.class_variable_get(:@@lessons_for_klasse)
        @@lessons = Main.class_variable_get(:@@lessons)
        @@faecher = Main.class_variable_get(:@@faecher)
        @@shorthands = Main.class_variable_get(:@@shorthands)
        @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        @@schueler_for_lesson = Main.class_variable_get(:@@schueler_for_lesson)
        @@lessons_for_shorthand = Main.class_variable_get(:@@lessons_for_shorthand)
        
#         @ocs.file_sharing.all.each do |share|
#             STDERR.puts sprintf('[%5s] %s => [%s]%s', share['id'], share['path'], share['share_with'], share['file_target'])
#             STDERR.puts share.to_yaml
#             @ocs.file_sharing.destroy(share['id'])
#         end
#         return
        
        wanted_shares = {}
        email_for_user_id = {}

        @@shorthands_for_lesson = {}
        @@lessons_for_shorthand.each_pair do |shorthand, item|
            item.each do |lesson_key|
                @@shorthands_for_lesson[lesson_key] ||= Set.new()
                @@shorthands_for_lesson[lesson_key] << shorthand
            end
        end
        
        @@lessons[:timetables][@@lessons[:timetables].keys.sort.last].keys.each do |lesson_key|
            lesson_info = @@lessons[:lesson_keys][lesson_key]
            # only handle lessons which have actual Klassen
            next if (Set.new(lesson_info[:klassen]) & Set.new(@@klassen_order)).empty?
            folder_name = "#{lesson_key}"
            fach = lesson_info[:fach]
            fach = @@faecher[fach] || fach
            pretty_folder_name = lesson_info[:pretty_folder_name]
            teachers = Set.new(lesson_info[:lehrer])
            teachers |= @@shorthands_for_lesson[lesson_key] || Set.new()
            teachers.each do |shorthand|
                email = @@shorthands[shorthand]
                next if email.nil?
                user = @@user_info[email]
                user_id = user[:nc_login]
                email_for_user_id[user_id] = email
                wanted_shares[user_id] ||= {}
                wanted_shares[user_id]["/Unterricht/#{folder_name}"] = {
                    :permissions => SHARE_READ | SHARE_UPDATE | SHARE_CREATE | SHARE_DELETE,
                    :target_path => "/Unterricht/#{pretty_folder_name}",
                    :share_with => user[:display_name]
                }
            end
            (@@schueler_for_lesson[lesson_key] || []).each do |email|
                user = @@user_info[email]
                name = user[:display_name]
                user_id = user[:nc_login]
                email_for_user_id[user_id] = email
                wanted_shares[user_id] ||= {}
                pretty_folder_name = "#{fach.gsub('/', '-')}"
                wanted_shares[user_id]["/Unterricht/#{folder_name}/Ausgabeordner"] = {
                    :permissions => SHARE_READ,
                    :target_path => "/Unterricht/#{pretty_folder_name.gsub(' ', '%20')}/Ausgabeordner",
                    :share_with => user[:display_name]
                }
                wanted_shares[user_id]["/Unterricht/#{folder_name}/SuS/#{name}/Einsammelordner"] = {
                    :permissions => SHARE_READ | SHARE_UPDATE | SHARE_CREATE | SHARE_DELETE,
                    :target_path => "/Unterricht/#{pretty_folder_name.gsub(' ', '%20')}/Einsammelordner",
                    :share_with => user[:display_name]
                }
                wanted_shares[user_id]["/Unterricht/#{folder_name}/SuS/#{name}/Rückgabeordner"] = {
                    :permissions => SHARE_READ | SHARE_UPDATE | SHARE_CREATE | SHARE_DELETE,
                    :target_path => "/Unterricht/#{pretty_folder_name.gsub(' ', '%20')}/Rückgabeordner",
                    :share_with => user[:display_name]
                }
            end
            next
        end
        wanted_shares.keys.each do |user_id|
            src_for_target_path = {}
            wanted_shares[user_id].each_pair do |src, info|
                src_for_target_path[info[:target_path]] ||= Set.new()
                src_for_target_path[info[:target_path]] << src
            end
            src_for_target_path.each_pair do |target_path, sources|
                if sources.size > 1
                    sources_sorted = sources.to_a.sort
                    sources_sorted[1, sources_sorted.size - 1].each do |src|
                        STDERR.puts "SKIPPING #{src}"
                        wanted_shares[user_id].delete(src)
                    end
                end
            end
            target_paths = wanted_shares[user_id].values.map { |x| x[:target_path] }
            if target_paths.sort.uniq.size != wanted_shares[user_id].size
                raise "Ouch! We didn't catch something in the code above."
            end
        end
        present_shares = {}
        (@ocs.file_sharing.all || []).each do |share|
            present_shares[share['share_with']] ||= {}
            present_shares[share['share_with']][share['path']] = {
                :permissions => share['permissions'].to_i,
                :target_path => share['file_target'],
                :share_with => share['share_with_displayname']
            }
        end
#         STDERR.puts present_shares.to_yaml
#         exit
        wanted_nc_ids = nil
        unless ARGV.empty?
            wanted_nc_ids = Set.new(ARGV.map { |email| (@@user_info[email] || {})[:nc_login] })
        end
        wanted_shares.keys.sort.each do |user_id|
            unless wanted_nc_ids.nil?
                next unless wanted_nc_ids.include?(user_id)
            end
            ocs_user = Nextcloud.ocs(url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER, 
                                     username: user_id,
                                     password: NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL)
            wanted_dirs = Set.new()
            wanted_shares[user_id].values.map { |x| x[:target_path] + '/' }.each do |path|
                parts = path.split('/')
                parts.each.with_index do |part, _|
                    sub_path = parts[0, _ + 1].join('/') + '/'
                    wanted_dirs << sub_path.gsub('%20', ' ') unless sub_path == '/' || sub_path == '/Unterricht/'
                end
            end
#             STDERR.puts wanted_dirs.to_a.sort.to_yaml
            result = []
            begin
                result = ocs_user.webdav.directory.find('/Unterricht').contents
            rescue NoMethodError => e
            end
            (result || []).each do |dir|
                unless dir.href.index("/remote.php/dav/files/#{user_id}") ==  0
                    STDERR.puts "Got unexpected dir: [#{user_id}]#{dir['href']}"
                    exit(1)
                end
                next unless dir.resourcetype == 'collection'
                path = dir.href.sub("/remote.php/dav/files/#{user_id}", '')
                path = CGI.unescape(path)
#                 STDERR.print "#{path} => "
                if wanted_dirs.include?(path)
#                     STDERR.puts "ok."
                else
                    dir2 = ocs_user.webdav.directory.find(path.gsub(' ', '%20'))
                    contents_count = (dir2.contents || []).size
                    if contents_count == 0
                        STDERR.puts "DELETING [#{user_id}]#{path}"
                        ocs_user.webdav.directory.destroy(path.gsub(' ', '%20'))
                    else
                        STDERR.puts "KEEPING [#{user_id}]#{path} because it has #{contents_count} files."
                    end
                end
            end
            created_sub_paths = Set.new()
            wanted_shares[user_id].each_pair do |path, info|
                next if (((present_shares[user_id] || {})[path]) || {})[:target_path] == info[:target_path]
                begin
                    unless (present_shares[user_id] || {})[path]
                        STDERR.puts "Sharing #{path} to [#{user_id}]..."
                        _temp = @ocs.file_sharing.create(path, 0, user_id, nil, nil, info[:permissions])
                    end
                    shares = (@ocs.file_sharing.specific(path.gsub(' ', '%20')) || []).select { |x| x['share_with'] == user_id }
                    if shares.size != 1
                        STDERR.puts "Could not find share of #{path} to [#{user_id}]..."
                        raise 'oops'
                    end
                    share = shares.first
                    if share['file_target'].gsub(' ', '%20') != info[:target_path]
                        dir_parts = File.dirname(info[:target_path]).split('/')
                        dir_parts.each.with_index do |p, _|
                            sub_path = dir_parts[0, _ + 1].join('/')
                            next if sub_path.empty?
                            unless created_sub_paths.include?(sub_path)
                                STDERR.puts "Creating [#{user_id}]#{sub_path}..."
                                ocs_user.webdav.directory.create(sub_path)
                                created_sub_paths << sub_path
                            end
                        end
                        STDERR.puts "Moving [#{user_id}]#{share['file_target']} to #{info[:target_path]}..."
                        result = ocs_user.webdav.directory.move(share['file_target'], info[:target_path])
                        if result[:status] != 'ok'
                            STDERR.puts "Error!"
                            exit(1)
                        end
                    end
                rescue StandardError => e
                end
            end
        end

    end
end

script = Script.new
script.run
