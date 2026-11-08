#!/usr/bin/env ruby
# Copies src/example-data for the test stack and moves the school year
# around today, so that timetables, lessons and homework exist for the
# current week (the example data itself is for a fixed school year).
#
#   ruby test/prepare_example_data.rb <source dir> <target dir>
#
# Called by ./test.sh before the test stack starts.

require 'date'
require 'fileutils'
require 'yaml'

source, target = ARGV
abort "usage: #{$0} <source> <target>" unless source && target && File.directory?(source)

FileUtils.rm_rf(target)
FileUtils.mkpath(File.dirname(target))
FileUtils.cp_r(source, target)

today = Date.today
monday = today - (today.cwday - 1)
first_school_day = monday - 4 * 7
last_day = monday + 26 * 7 - 3

File.write(File.join(target, 'config.yaml'), {
    :first_day => first_school_day.to_s,
    :first_school_day => first_school_day.to_s,
    :last_day => last_day.to_s,
}.to_yaml)

# Timetable and break duty files are named after the date they are valid
# from; files dated before the first school day are ignored.
%w(stundenplan pausenaufsichten).each do |dir|
    files = Dir[File.join(target, dir, '*.TXT')].sort
    next if files.empty?
    files[0, files.size - 1].each { |f| FileUtils.rm_f(f) }
    FileUtils.mv(files.last, File.join(target, dir, "#{first_school_day}.TXT"))
end

puts "Example data for the test stack: school year #{first_school_day} – #{last_day}"
