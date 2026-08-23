#!/usr/bin/env ruby

require 'cgi'

warn_level = $VERBOSE
$VERBOSE = nil
require './credentials.template.rb'
require './credentials.rb'
$VERBOSE = warn_level

require './nextcloud_client.rb'

SRSLY = ARGV.delete('--srsly')

unless ARGV.empty?
    STDERR.puts "Unknown arguments: #{ARGV.join(' ')}"
    exit 2
end

def normalize_path(path)
    decoded = CGI.unescape(path.to_s).unicode_normalize(:nfc)
    decoded = "/#{decoded}" unless decoded.start_with?('/')
    decoded = decoded.sub(%r{/+\z}, '') unless decoded == '/'
    decoded
end

def root_level_path?(path)
    normalize_path(path).split('/').reject(&:empty?).size == 1
end

ocs = DashboardNextcloud.admin

STDERR.puts "Collecting Dashboard shares from Nextcloud..."

shares = ocs.file_sharing.all || []

broken_shares = shares.select do |share|
    next false unless share['share_type'].to_i == 0

    source = normalize_path(share['path'])
    target = normalize_path(share['file_target'])

    source.start_with?('/Unterricht/') && root_level_path?(target)
end

if broken_shares.empty?
    puts "No broken root-level Unterricht shares found."
    exit 0
end

puts
puts "#{broken_shares.size} broken root-level Unterricht share(s) found:"
puts

broken_shares.sort_by do |share|
    [
        share['share_with'].to_s,
        normalize_path(share['file_target']),
        normalize_path(share['path'])
    ]
end.each do |share|
    puts "[#{share['share_with']}] share ##{share['id']}"
    puts "  source: #{normalize_path(share['path'])}"
    puts "  target: #{normalize_path(share['file_target'])}"
    puts
end

unless SRSLY
    puts "Dry run: nothing was changed."
    puts "Run again with --srsly to remove exactly these shares."
    exit 0
end

puts "Removing broken shares..."
puts

errors = []

broken_shares.each do |share|
    begin
        print "[#{share['share_with']}] ##{share['id']} #{normalize_path(share['file_target'])}... "
        ocs.file_sharing.destroy(share['id'])
        puts "removed"
    rescue StandardError => e
        puts "ERROR"
        STDERR.puts "  #{e.class}: #{e.message}"
        errors << share['id']
    end
end

puts
puts "Removed #{broken_shares.size - errors.size} of #{broken_shares.size} broken share(s)."

unless errors.empty?
    STDERR.puts "Failed share IDs: #{errors.join(', ')}"
    exit 1
end

puts "Now run share-nc-folders.rb --srsly to recreate the wanted shares in /Unterricht."
