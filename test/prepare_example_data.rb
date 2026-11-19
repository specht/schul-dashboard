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

# A subject teacher with 5a in room 317, where Clarke (class teacher of 5a)
# also teaches it; the homeroom stays 108 (sitzplan-fachraum.spec.ts).
File.open(File.join(target, 'stundenplan', "#{first_school_day}.TXT"), 'a') do |f|
    f.puts '7,"5a","Fr","Nawi","317",1,3,,'
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
    # teaches 5a in a subject room, not its homeroom (sitzplan-fachraum.spec.ts)
    'fachraum@beispielschule.de,Fr,w,Fachraum,Frieda,,',
    # a teacher who also manages the library (design-preview-bib.spec.ts)
    'bib.lehrkraft@beispielschule.de,Bk,w,Lesemann,Berta,,',
    # only for otp-nudge.spec.ts: SMS login without a code app (one per
    # Playwright project, see test/e2e/seed.cypher)
    'sms.eins@beispielschule.de,Se,w,Eins,Sina,,',
    'sms.zwei@beispielschule.de,Sz,m,Zwei,Sven,,',
    # extended staff: Kürzel with a leading underscore (Gruppenbildung Kollegium)
    'sozialarbeit@beispielschule.de,_Ss,w,Sozial,Sarah,,',
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
    'CAN_MANAGE_ANTIKENFAHRT' => ['zeugnis.admin@beispielschule.de'],
    'TECHNIKTEAM' => ['technik@beispielschule.de'],
    'CAN_USE_AULA' => ['technik@beispielschule.de'],
    'CAN_MANAGE_NEWS' => ['technik@beispielschule.de'],
    'CAN_MANAGE_MONITORS' => ['technik@beispielschule.de'],
    'SEKRETARIAT' => ['sekretariat@beispielschule.de'],
    'MITTAGESSEN' => ['sekretariat@beispielschule.de'],
    'CAN_PRINT_PHOTOS' => ['sekretariat@beispielschule.de'],
    'CAN_MANAGE_BIB' => ['bibliothek@beispielschule.de', 'bib.lehrkraft@beispielschule.de'],
    'CAN_MANAGE_BIB_MEMBERS' => ['bibliothek@beispielschule.de'],
    'CAN_MANAGE_BIB_PAYMENT' => ['bibliothek@beispielschule.de'],
    'GEV' => ['gev@beispielschule.de'],
    'EXTERNE_AG_LEITUNG' => ['externe.ag@beispielschule.de'],
    'SV' => ['elli.mustermann@mail.beispielschule.de'],
    'SV_EDITOR' => ['elli.mustermann@mail.beispielschule.de'],
    # the admin also answers the Datentresor hotline (design-preview-start.spec.ts)
    'DATENTRESOR_HOTLINE' => ['clarke@beispielschule.de'],
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
# 5th graders sometimes has none yet), for the LogoDIDACT export
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

# Klassenmemory (/klassenmemory_assign, design-preview-klassenmemory.spec.ts):
# the example data has no class photos. Drawn placeholder portraits (a head
# and shoulders, no real person), encrypted like the photos of a real photo
# session with the password KLASSENMEMORY_PASSWORD (typed into the page;
# FOTO_PASSWORD stays nil in the test stack). The ones named
# "beispielfoto-<account>" are assigned to these students in
# test/e2e/seed.cypher (keep both lists in step); two photos of 5a's photo
# session have no name yet ("<year>-5a-<n>"). Plus /data/jauch.png, the
# picture next to the Hall of Fame.
require 'base64'
require 'json'
require 'openssl'
require 'zlib'

KLASSENMEMORY_PASSWORD = 'beispielfotos'
KLASSENMEMORY_PHOTOS = %w(max.mustermann elli.mustermann anonymous.2342) +
    GROUP_TEST_FIRST_NAMES.map { |n| "#{n.downcase}.gruppentest" } +
    GROUP_TEST_FIRST_NAMES.map { |n| "#{n.downcase}.labtest" }

def png_bytes(width, height)
    rows = (0...height).map do |y|
        "\0".b + (0...width).map { |x| yield(x, y).pack('C4') }.join
    end
    chunk = lambda do |type, data|
        [data.bytesize].pack('N') + type.b + data + [Zlib.crc32(type + data)].pack('N')
    end
    "\x89PNG\r\n\x1a\n".b +
        chunk.call('IHDR', [width, height, 8, 6, 0, 0, 0].pack('NNCCCCC')) +
        chunk.call('IDAT', Zlib::Deflate.deflate(rows.join)) +
        chunk.call('IEND', ''.b)
end

# head and shoulders on a soft background, each in colours of its own
def placeholder_portrait(i)
    hue = (i * 47) % 360
    rgb = lambda do |s, l|
        c = (1 - (2 * l - 1).abs) * s
        x = c * (1 - ((hue / 60.0) % 2 - 1).abs)
        r, g, b = [[c, x, 0], [x, c, 0], [0, c, x], [0, x, c], [x, 0, c], [c, 0, x]][hue / 60]
        [r, g, b].map { |v| ((v + l - c / 2) * 255).round } + [255]
    end
    ground, person = rgb.call(0.45, 0.82), rgb.call(0.35, 0.42)
    png_bytes(160, 240) do |x, y|
        head = (x - 80)**2 + (y - 100)**2 <= 38**2
        shoulders = ((x - 80) / 70.0)**2 + ((y - 245) / 85.0)**2 <= 1
        head || shoulders ? person : ground
    end
end

# as the page decrypts it: PBKDF2 (SHA-1, 20000 rounds), AES-256-CBC, the
# image as base64 inside
def encrypt_photo(bytes, password)
    salt = OpenSSL::Random.random_bytes(16)
    iv = OpenSSL::Random.random_bytes(16)
    cipher = OpenSSL::Cipher.new('AES-256-CBC').encrypt
    cipher.key = OpenSSL::PKCS5.pbkdf2_hmac_sha1(password, salt, 20000, 32)
    cipher.iv = iv
    data = cipher.update(Base64.strict_encode64(bytes)) + cipher.final
    {:salt => Base64.strict_encode64(salt), :iv => Base64.strict_encode64(iv),
     :data => Base64.strict_encode64(data)}.to_json
end

foto_dir = File.join(target, 'schueler', 'fotos')
FileUtils.mkpath(foto_dir)
(KLASSENMEMORY_PHOTOS.map { |account| "beispielfoto-#{account}" } +
 (1..2).map { |n| "#{first_school_day.year}-5a-#{n}" }).each_with_index do |name, i|
    File.write(File.join(foto_dir, name), encrypt_photo(placeholder_portrait(i), KLASSENMEMORY_PASSWORD))
end
File.binwrite(File.join(target, 'jauch.png'), png_bytes(120, 160) do |x, y|
    head = (x - 60)**2 + (y - 40)**2 <= 24**2
    body = ((x - 60) / 50.0)**2 + ((y - 175) / 105.0)**2 <= 1
    head || body ? [120, 128, 140, 255] : [0, 0, 0, 0]
end)

puts "Example data for the test stack: school year #{first_school_day} – #{last_day}, with extra role accounts"
