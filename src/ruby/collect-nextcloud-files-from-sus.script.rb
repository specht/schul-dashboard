#!/usr/bin/env ruby
# encoding: UTF-8

require 'date'
require 'fileutils'
require 'set'
require 'yaml'

NEXTCLOUD_DASHBOARD_DATA_DIRECTORY = __NEXTCLOUD_DASHBOARD_DATA_DIRECTORY__
DRY_RUN = __DRY_RUN__
NEXTCLOUD_WAIT_SECONDS = __NEXTCLOUD_WAIT_SECONDS__

if DRY_RUN
    STDERR.puts "DRY RUN (not making any changes to the filesystem)"
    STDERR.puts "To make changes to the filesystem, specify --srsly on the command line."
end

DASH = '–'

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

refresh_dirs = Set.new()

BASE_DIR = File.join(NEXTCLOUD_DASHBOARD_DATA_DIRECTORY, 'files', 'Unterricht')

skipped_return_lesson_keys = Set.new()
STDERR.puts "Checking for files to collect..."
Dir[File.join(BASE_DIR, '*/SuS/*/Einsammelordner/Eingesammelt/*')].reject do |x|
end.reject do |x|
    abspath = File.absolute_path(x)
    relpath = abspath.sub(BASE_DIR, '')
    parts = relpath.split('/')
    parts.shift if parts.first.empty?
    lesson_key = parts[0]
    name = parts[2]
    (Time.now < File.mtime(x) + NEXTCLOUD_WAIT_SECONDS) || (File.basename(relpath).index("#{name} #{DASH}") == 0)
end.each do |x|
    abspath = File.absolute_path(x)
    relpath = abspath.sub(BASE_DIR, '')
    parts = relpath.split('/')
    parts.shift if parts.first.empty?
    lesson_key = parts[0]
    name = parts[2]
    basename = parts.last
    target_filename = basename
    cp_target_dir = '/dev/null'
    mv_target_dir = File.expand_path(File.join(File.dirname(File.join(BASE_DIR, parts)), '..'))
    cp_path, mv_path = find_available_target_paths(target_filename, cp_target_dir, mv_target_dir)
    # can be omitted because source path already gets refreshed
    refresh_dirs << File.dirname(mv_path)
    unless DRY_RUN
        unless File.exists?(File.dirname(mv_path))
            FileUtils::mkpath(File.dirname(mv_path))
        end
        FileUtils::mv(x, mv_path)
    end
end

Dir[File.join(BASE_DIR, '*/SuS/*/Einsammelordner/*')].reject do |x|
    File.basename(x) == 'Eingesammelt' || File.basename(x) == 'Readme.md'
end.reject do |x|
    Time.now < File.mtime(x) + NEXTCLOUD_WAIT_SECONDS
end.each do |x|
    abspath = File.absolute_path(x)
    relpath = abspath.sub(BASE_DIR, '')
    parts = relpath.split('/')
    parts.shift if parts.first.empty?
    lesson_key = parts[0]
    name = parts[2]
    # ---------------------------------
    # next unless name == '[insert name here]'
    # ---------------------------------
    basename = parts.last
    target_filename = "#{name} #{DASH} #{basename}"
    cp_target_dir = Dir[File.join(BASE_DIR, lesson_key, '*')].select do |y|
        File.basename(y).index('Auto-Einsammelordner') == 0
    end.first
    if cp_target_dir.nil?
        STDERR.puts '=' * 50
        STDERR.puts "missing Auto-Einsammelordner for #{lesson_key}!"
        STDERR.puts '=' * 50
        next
    end
    mv_target_dir = File.dirname(File.join(BASE_DIR, parts.insert(-2, 'Eingesammelt')))
    cp_path, mv_path = find_available_target_paths(target_filename, cp_target_dir, mv_target_dir)
    STDERR.puts "cp -al [#{x}] => [#{cp_path}]"
    refresh_dirs << File.dirname(x)
    refresh_dirs << File.dirname(cp_path)
    unless DRY_RUN
        system('cp', '-al', x, cp_path)
    end
    STDERR.puts "mv [#{x}] => [#{mv_path}]"
    unless DRY_RUN
        unless File.exists?(File.dirname(mv_path))
            FileUtils::mkpath(File.dirname(mv_path))
        end
        FileUtils::mv(x, mv_path)
    end
end

STDERR.puts "Checking for files to hand out..."
Dir[File.join(BASE_DIR, '*/Auto-Rückgabeordner (von mir an SuS)/*')].reject do |x|
    File.basename(x) == 'Zurückgegeben' || File.basename(x) == 'Readme.md'
end.reject do |x|
    Time.now < File.mtime(x) + NEXTCLOUD_WAIT_SECONDS
end.each do |x|
    abspath = File.absolute_path(x)
    relpath = abspath.sub(BASE_DIR, '')
    parts = relpath.split('/')
    parts.shift if parts.first.empty?
    lesson_key = parts[0]
    filename_with_name_parts = Set.new(parts[2].downcase.split(/[\s\-\._\d]+/)) - NAME_MATCH_STOP_WORDS
    matches_per_name = {}
    Dir[File.join(BASE_DIR, lesson_key, 'SuS', '*')].each do |sus_path|
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
        cp_target_dir = File.join(BASE_DIR, lesson_key, 'SuS', name, 'Rückgabeordner')
        mv_target_dir = File.dirname(File.join(BASE_DIR, parts.insert(-2, 'Zurückgegeben')))
        cp_path, mv_path = find_available_target_paths(target_filename, cp_target_dir, mv_target_dir)
        STDERR.puts "cp -al [#{x}] => [#{cp_path}]"
        refresh_dirs << File.dirname(x)
        refresh_dirs << File.dirname(cp_path)
        unless DRY_RUN
            begin
                system('cp', '-al', x, cp_path)
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
            end
        end
        STDERR.puts "mv [#{x}] => [#{mv_path}]"
        unless DRY_RUN
            begin
                FileUtils::mv(x, mv_path)
            rescue StandardError => e
                STDERR.puts '-' * 60
                STDERR.puts 'MOVE FAILED.'
                STDERR.puts '-' * 60
            end
        end
    else
        # We couldn't find an unambiguous match, do nothing.
        STDERR.puts "Found no match for: #{relpath}, skipping..."
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
    dir = _.sub(File::dirname(NEXTCLOUD_DASHBOARD_DATA_DIRECTORY), '').sub(/^\//, '')
    STDERR.puts "Refreshing #{dir}"
    unless DRY_RUN
        command = "php occ files:scan -v --path=\"#{dir}\" #{File::basename(NEXTCLOUD_DASHBOARD_DATA_DIRECTORY)}"
        system(command)
    end
end
