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

# More accounts and roles than the example data has, so that tests and the
# UI tour cover the role spectrum of a real school. Must match ROLE_ACCOUNTS
# in test/e2e/tests/fixtures.ts.
def append_lines(path, lines)
    text = File.exist?(path) ? File.read(path) : ''
    text += "\n" unless text.empty? || text.end_with?("\n")
    File.write(path, text + lines.join("\n") + "\n")
end

append_lines(File.join(target, 'lehrer', 'lehrer.csv'), [
    'zeugnis.admin@beispielschule.de,Za,w,Zeugnis,Zoe,,',
    'technik@beispielschule.de,Tk,m,Technik,Tom,,',
])
append_lines(File.join(target, 'extra-dashboard-accounts.csv'), [
    'sekretariat@beispielschule.de,w,Sekretariat,Sabine,',
    'bibliothek@beispielschule.de,m,Bibliothek,Ben,',
    'gev@beispielschule.de,w,Elternvertretung,Gabi,',
    'externe.ag@beispielschule.de,m,Extern,Erik,',
])
{
    'ZEUGNIS_ADMIN' => ['zeugnis.admin@beispielschule.de'],
    'OKO' => ['zeugnis.admin@beispielschule.de'],
    'CAN_SEE_KURSLISTEN' => ['zeugnis.admin@beispielschule.de'],
    'CAN_MANAGE_PROJEKTTAGE' => ['zeugnis.admin@beispielschule.de'],
    'CAN_MANAGE_LAB8' => ['zeugnis.admin@beispielschule.de'],
    'CAN_MANAGE_LAB9' => ['zeugnis.admin@beispielschule.de'],
    'TECHNIKTEAM' => ['technik@beispielschule.de'],
    'CAN_USE_AULA' => ['technik@beispielschule.de'],
    'CAN_MANAGE_NEWS' => ['technik@beispielschule.de'],
    'CAN_MANAGE_MONITORS' => ['technik@beispielschule.de'],
    'SEKRETARIAT' => ['sekretariat@beispielschule.de'],
    'MITTAGESSEN' => ['sekretariat@beispielschule.de'],
    'CAN_PRINT_PHOTOS' => ['sekretariat@beispielschule.de'],
    'CAN_MANAGE_BIB' => ['bibliothek@beispielschule.de'],
    'CAN_MANAGE_BIB_MEMBERS' => ['bibliothek@beispielschule.de'],
    'CAN_MANAGE_BIB_PAYMENT' => ['bibliothek@beispielschule.de'],
    'GEV' => ['gev@beispielschule.de'],
    'EXTERNE_AG_LEITUNG' => ['externe.ag@beispielschule.de'],
    'SV' => ['elli.mustermann@mail.beispielschule.de'],
    'SV_EDITOR' => ['elli.mustermann@mail.beispielschule.de'],
}.each_pair do |role, emails|
    append_lines(File.join(target, 'roles', 'roles.txt'), [">> #{role}"] + emails)
end

# Lab 8/9: the real configuration decides who takes part (by grade); in the
# test stack the students of class 5a do, so the pages can be tested.
%w(lab8 lab9).each do |lab|
    append_lines(File.join(target, lab, 'config.rb'), [
        "# test stack (test/prepare_example_data.rb): students of class 5a take part",
        "def email_is_eligible_for_#{lab}?(user_info, email)",
        "    (user_info[email] || {})[:klasse] == '5a'",
        "end",
    ])
end

puts "Example data for the test stack: school year #{first_school_day} – #{last_day}, with extra role accounts"
