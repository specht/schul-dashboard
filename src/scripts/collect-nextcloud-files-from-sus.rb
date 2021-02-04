#!/usr/bin/env ruby

require 'date'
require 'fileutils'
require 'set'
require 'yaml'

if Process.uid != 0
    STDERR.puts "This script must be run as root!"
    exit(1)
end

DRY_RUN = !(ARGV.first == '--srsly')

if DRY_RUN
    STDERR.puts "DRY RUN (not making any changes to the filesystem)"
end

DASH = '–'

DASHBOARD_BASE_DIR = '/www/data/nextcloud/Dashboard/files/Unterricht/'
WAIT_SECONDS = 5 * 60
NAME_MATCH_STOP_WORDS = Set.new(['de', 'la', 'von'])

def find_available_target_paths(target_filename, cp_target_dir, mv_target_dir)
    n = 1
    while true do
        temp_target_filename = target_filename.dup
        if n > 1
            temp_parts = target_filename.split('.')
            inject_index = temp_parts.size - 2
            inject_index = 0 if inject_index < 0
            temp_parts[inject_index] += " (#{n})"
            temp_target_filename = temp_parts.join('.')
        end
        cp_path = File.join(cp_target_dir, temp_target_filename)
        mv_path = File.join(mv_target_dir, temp_target_filename)
        unless File.exists?(cp_path) || File.exists?(mv_path)
            return cp_path, mv_path
        end
        n += 1
    end
end

while true do
    now = Time.now
    next_round = now + 5 * 60 # next round in five minutes
    refresh_dirs = Set.new()
    
    skipped_return_lesson_keys = Set.new()
    STDERR.puts "Checking for files to collect..."
    Dir[File.join(DASHBOARD_BASE_DIR, '*/SuS/*/Einsammelordner/Eingesammelt/*')].reject do |x|
    end.reject do |x|
        Time.now < File.mtime(x) + WAIT_SECONDS
        # ---------------------------------
        abspath = File.absolute_path(x)
        relpath = abspath.sub(DASHBOARD_BASE_DIR, '')
        parts = relpath.split('/')
        lesson_key = parts[0]
        name = parts[2]
        File.basename(relpath).index("#{name} #{DASH}") == 0
        # ---------------------------------
    end.each do |x|
        abspath = File.absolute_path(x)
        relpath = abspath.sub(DASHBOARD_BASE_DIR, '')
        parts = relpath.split('/')
        lesson_key = parts[0]
        name = parts[2]
        # ---------------------------------
        # next unless name == '[insert name here]'
        # ---------------------------------
        basename = parts.last
        target_filename = basename
        cp_target_dir = '/dev/null'
        mv_target_dir = File.expand_path(File.join(File.dirname(File.join(DASHBOARD_BASE_DIR, parts)), '..'))
#         STDERR.puts "target_filename = #{target_filename}"
#         STDERR.puts "mv_target_dir = #{mv_target_dir}"
        cp_path, mv_path = find_available_target_paths(target_filename, cp_target_dir, mv_target_dir)
#         STDERR.puts "mv_path = #{mv_path}"
#         STDERR.puts "mv [#{x}] => [#{mv_path}]"
        # can be omitted because source path already gets refreshed
        refresh_dirs << File.dirname(mv_path)
        unless DRY_RUN
            unless File.exists?(File.dirname(mv_path))
                FileUtils::mkpath(File.dirname(mv_path))
                FileUtils::chown_R('www-data', 'users', File.dirname(mv_path))
            end
            FileUtils::mv(x, mv_path)
            FileUtils::chown_R('www-data', 'users', mv_path)
        end
    end

    Dir[File.join(DASHBOARD_BASE_DIR, '*/SuS/*/Einsammelordner/*')].reject do |x|
        File.basename(x) == 'Eingesammelt' || File.basename(x) == 'Readme.md'
    end.reject do |x|
        Time.now < File.mtime(x) + WAIT_SECONDS
        # ---------------------------------
        false
        # ---------------------------------
    end.each do |x|
        abspath = File.absolute_path(x)
        relpath = abspath.sub(DASHBOARD_BASE_DIR, '')
        parts = relpath.split('/')
        lesson_key = parts[0]
        name = parts[2]
        # ---------------------------------
        # next unless name == '[insert name here]'
        # ---------------------------------
        basename = parts.last
        target_filename = "#{name} #{DASH} #{basename}"
        cp_target_dir = Dir[File.join(DASHBOARD_BASE_DIR, lesson_key, '*')].select do |y|
            File.basename(y).index('Auto-Einsammelordner') == 0
        end.first
        if cp_target_dir.nil?
            STDERR.puts '=' * 50
            STDERR.puts "missing Auto-Einsammelordner for #{lesson_key}!"
            STDERR.puts '=' * 50
            next
        end
        mv_target_dir = File.dirname(File.join(DASHBOARD_BASE_DIR, parts.insert(-2, 'Eingesammelt')))
#         STDERR.puts "target_filename = #{target_filename}"
#         STDERR.puts "cp_target_dir = #{cp_target_dir}"
#         STDERR.puts "mv_target_dir = #{mv_target_dir}"
        cp_path, mv_path = find_available_target_paths(target_filename, cp_target_dir, mv_target_dir)
#         STDERR.puts "cp_path = #{cp_path}"
#         STDERR.puts "mv_path = #{mv_path}"
        STDERR.puts "cp [#{x}] => [#{cp_path}]"
        refresh_dirs << File.dirname(x)
        refresh_dirs << File.dirname(cp_path)
        unless DRY_RUN
            FileUtils::cp_r(x, cp_path)
            FileUtils::chown_R('www-data', 'users', cp_path)
        end
        STDERR.puts "mv [#{x}] => [#{mv_path}]"
        # can be omitted because source path already gets refreshed
#         refresh_dirs << File.dirname(mv_path)
        unless DRY_RUN
            unless File.exists?(File.dirname(mv_path))
                FileUtils::mkpath(File.dirname(mv_path))
                FileUtils::chown_R('www-data', 'users', File.dirname(mv_path))
            end
            FileUtils::mv(x, mv_path)
            FileUtils::chown_R('www-data', 'users', mv_path)
        end
    end

    STDERR.puts "Checking for files to hand out..."
    Dir[File.join(DASHBOARD_BASE_DIR, '*/Auto-Rückgabeordner (von mir an SuS)/*')].reject do |x|
        File.basename(x) == 'Zurückgegeben' || File.basename(x) == 'Readme.md'
    end.reject do |x|
        Time.now < File.mtime(x) + WAIT_SECONDS
        # ---------------------------------
        # false
        # ---------------------------------
    end.each do |x|
        abspath = File.absolute_path(x)
        relpath = abspath.sub(DASHBOARD_BASE_DIR, '')
        parts = relpath.split('/')
        lesson_key = parts[0]
        filename_with_name_parts = Set.new(parts[2].downcase.split(/[\s\-\._\d]+/)) - NAME_MATCH_STOP_WORDS
        matches_per_name = {}
        Dir[File.join(DASHBOARD_BASE_DIR, lesson_key, 'SuS', '*')].each do |sus_path|
            name = sus_path.split('/').last
            name_parts = Set.new(name.downcase.split(/[\s\-]+/)) - NAME_MATCH_STOP_WORDS
            matches_per_name[name] = (name_parts & filename_with_name_parts).size
        end
        max_match = matches_per_name.values.max
        matches = matches_per_name.keys.select do |name|
            matches_per_name[name] == max_match
        end
        max_match ||= 0
        if max_match > 0 && matches.size == 1
            # We found an unambiguous name match, hand out the file.
            name = matches.first
            STDERR.puts "[#{parts[2]}] found match: #{name}"
            target_filename = File.basename(x)
            basename = parts.last
            cp_target_dir = File.join(DASHBOARD_BASE_DIR, lesson_key, 'SuS', name, 'Rückgabeordner')
            mv_target_dir = File.dirname(File.join(DASHBOARD_BASE_DIR, parts.insert(-2, 'Zurückgegeben')))
#             STDERR.puts "target_filename = #{target_filename}"
#             STDERR.puts "cp_target_dir = #{cp_target_dir}"
#             STDERR.puts "mv_target_dir = #{mv_target_dir}"
            cp_path, mv_path = find_available_target_paths(target_filename, cp_target_dir, mv_target_dir)
#             STDERR.puts "cp_path = #{cp_path}"
#             STDERR.puts "mv_path = #{mv_path}"
            STDERR.puts "cp [#{x}] => [#{cp_path}]"
            refresh_dirs << File.dirname(x)
            refresh_dirs << File.dirname(cp_path)
            unless DRY_RUN
                begin
                    FileUtils::cp_r(x, cp_path)
                    FileUtils::chown_R('www-data', 'users', cp_path)
                rescue StandardError => e
                    STDERR.puts '-' * 60
                    STDERR.puts 'COPY FAILED.'
                    STDERR.puts '-' * 60
                end
            end
            STDERR.puts "Checking: #{File.dirname(mv_path)}"
            unless File.exists?(File.dirname(mv_path))
                STDERR.puts "md [#{File.dirname(mv_path)}]"
                unless DRY_RUN
                    FileUtils::mkdir(File.dirname(mv_path))
                    FileUtils::chown_R('www-data', 'users', File.dirname(mv_path))
                end
            end
            STDERR.puts "mv [#{x}] => [#{mv_path}]"
#             refresh_dirs << File.dirname(mv_path)
            unless DRY_RUN
                begin
                    FileUtils::mv(x, mv_path)
                    FileUtils::chown_R('www-data', 'users', mv_path)
                rescue StandardError => e
                    STDERR.puts '-' * 60
                    STDERR.puts 'MOVE FAILED.'
                    STDERR.puts '-' * 60
                end
            end
        else
            # We couldn't find an unambiguous match, do nothing.
            STDERR.puts "[#{parts[2]}] found no match, skipping"
            skipped_return_lesson_keys << lesson_key
        end
    end
    unless skipped_return_lesson_keys.empty?
        STDERR.puts '=' * 50
        STDERR.puts "THE FOLLOWING LESSON KEYS HAVE UNRETURNABLE FILES:"
        STDERR.puts skipped_return_lesson_keys.to_a.sort.to_yaml
        STDERR.puts '=' * 50
    end

    refresh_dirs.to_a.sort.each do |_|
        dir = _.sub('/www/data/nextcloud', '')
        STDERR.puts "Refreshing #{dir}"
        unless DRY_RUN
            command = "sudo --user www-data php /www/vhosts/nextcloud/occ files:scan -v --path=\"#{dir}\" Dashboard"
            system(command)
        end
    end

    STDERR.puts "Waiting until #{next_round}..."
    while Time.now < next_round
        sleep 10.0
    end
end
