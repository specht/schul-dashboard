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
    # only for the test of the login attempt limit (login-codes.smoke.ts) –
    # it leaves open login attempts behind, no other test may use it
    'anmeldelimit@beispielschule.de,w,Limit,Lina,',
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
# test stack the students of class 5a do, so the pages can be tested, and
# the group test students of class 11 (see below).
%w(lab8 lab9).each do |lab|
    append_lines(File.join(target, lab, 'config.rb'), [
        "# test stack (test/prepare_example_data.rb): students of class 5a take part",
        "# (and the Labtest students of class 11 for the group tests)",
        "def email_is_eligible_for_#{lab}?(user_info, email)",
        "    info = user_info[email] || {}",
        "    info[:klasse] == '5a' || (info[:klasse] == '11' && info[:last_name] == 'Labtest')",
        "end",
    ])
end

# Student groups (Projekttage, Lab 8/9, Pk5): students for the group tests
# (test/e2e/tests/student-groups.spec.ts), each test project (desktop,
# mobile) uses its own three per module. Class 11 organizes Projekttage, class
# 12 is PK5_CURRENT_KLASSE (credentials.template.rb); the Labtest students
# (class 11) take part in Lab 8/9 (see above). Not in 5a: other tests rely on
# its size (sitzplan.spec.ts: eight seats).
GROUP_TEST_FIRST_NAMES = %w(Anna Ben Cem Dana Emil Fiona)
# The Postfachtest students are for the mailbox password reset
# (test/e2e/tests/mail-password-reset.spec.ts).
{ 'Gruppentest' => '11', 'Pruefungstest' => '12', 'Labtest' => '11', 'Postfachtest' => '11' }.each_pair do |last_name, klasse|
    append_lines(File.join(target, 'schueler', 'ASCII.TXT'), GROUP_TEST_FIRST_NAMES.map.with_index do |first_name, i|
        "#{last_name}\t#{first_name}\t#{klasse}\t#{i.even? ? 'w' : 'm'}\t01.0#{i + 1}.2010"
    end)
end

# A student without a birthday in the student list (the student list of new
# 5th graders sometimes has none yet), for the LoGoDidact export
# (test/e2e/tests/admin-exports.spec.ts).
append_lines(File.join(target, 'schueler', 'ASCII.TXT'), ["Ohnegeburtstag\tGina\t11\tw\t"])

# A Klassenleitung that is not an admin (the admin account leads 5a):
# Torsta Torstensonin leads class 11.
append_lines(File.join(target, 'klassenleiter', 'klassenleiter.txt'), ['11,Ta'])

# Projekttage and Pk5 are planned in phases; the real configuration (input
# data) defines them with PhasedEvent. In the test stack there is a single
# phase in which students may edit everything.
File.write(File.join(target, 'phased_event.rb'), <<~'RUBY')
    # test stack (test/prepare_example_data.rb): same interface as the
    # PhasedEvent of the real input data
    class PhasedEvent
        def initialize()
            @phases = []
        end

        attr_reader :phases

        def add_phase(section:, index:, t0:, t1:, label:, flags: [], description:)
            raise 'Index mismatch' unless index == @phases.length
            @phases << {section: section, index: index, t0: t0, t1: t1, label: label, flags: flags, description: description}
        end

        def get_current_phase()
            ts = Time.now.strftime('%Y-%m-%dT%H:%M:%S')
            phase_index = -1
            while (phase_index < @phases.length - 1) && (ts >= @phases[phase_index + 1][:t0])
                phase_index += 1
            end
            phase_index
        end

        def print_schedule()
            phase = @phases[get_current_phase()]
            "<div>Aktuelle Phase: <strong>#{CGI.escapeHTML(phase[:label])}</strong></div>"
        end
    end
RUBY
{ 'projekte' => '$projekttage', 'pk5' => '$pk5' }.each_pair do |dir, variable|
    append_lines(File.join(target, dir, 'config.rb'), [
        "# test stack (test/prepare_example_data.rb): one open phase",
        "require File.join(File.dirname(__FILE__), '..', 'phased_event.rb')",
        "#{variable} = PhasedEvent.new",
        "#{variable}.add_phase(section: 1, index: 0, t0: '2000-01-01T00:00:00', t1: '2100-01-01T00:00:00', label: 'Testphase', description: 'Alles kann bearbeitet werden.')",
    ])
end
append_lines(File.join(target, 'pk5', 'config.rb'), [
    "PK5_PUBLISH_FINAL_THEMA = '2100-01-01T00:00'",
])
append_lines(File.join(target, 'projekte', 'config.rb'), [
    "def email_is_projekttage_organizer?(user_info, email)",
    "    (user_info[email] || {})[:klasse] == '11'",
    "end",
    "def projekttage_phase",
    "    1",
    "end",
])

# A public event (sign-up without login, e.g. open day) – the example data
# has none.
FileUtils.mkpath(File.join(target, 'public_events'))
File.write(File.join(target, 'public_events', 'public_events.yaml'), [{
    :key => 'tag-der-offenen-tuer',
    :title => 'Tag der offenen Tür',
    :description => 'Anmeldung zum Tag der offenen Tür',
    :headings => ['Tag', 'Uhrzeit'],
    :mail_subject => 'Anmeldung zum Tag der offenen Tür',
    :mail_text => "<p>Hallo!</p><p>Sie sind angemeldet: {row[:description]}, {entry[:description]}.</p>",
    :rows => [{
        :description => 'Samstag',
        :entries => [{:key => 'vormittag', :description => '10:00 Uhr', :label => '10:00', :capacity => 100}],
    }],
}].to_yaml)

puts "Example data for the test stack: school year #{first_school_day} – #{last_day}, with extra role accounts"
