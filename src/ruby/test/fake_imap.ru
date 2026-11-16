# A stand-in for the mail provider's IMAP server in the test stack
# (env.test.rb, service "imap"), for the mailbox check on /postfaecher
# (include/mailbox_check.rb). Speaks just enough IMAP for Net::IMAP: LOGIN,
# CAPABILITY, LIST, STATUS, EXAMINE, SEARCH, FETCH (INTERNALDATE only),
# GETQUOTAROOT, LOGOUT. A login only works with the original password from the
# E-Mail-Brief, computed like Main.gen_password_for_email with the test salt.
# The mailboxes hold no mails, only their arrival dates.
#
#   IMAP on port 1143 (from the stack: imap:1143, no TLS)
#   POST   /_mailbox     {user, accept: 'original' | 'never', folders: [{name, dates: [ISO]}],
#                         quota: {used_kb, limit_kb} | null}
#   DELETE /_mailboxes   forget all mailboxes and the log
#   GET    /_log         the commands received [{user, command, args}] (passwords left out)
#
# Reachable from the host on 127.0.0.1:8128 (tests).

require 'date'
require 'digest'
require 'json'
require 'rack'
require 'socket'
require 'time'

Dir.chdir('/app') { require './test/credentials.rb' }

MAILBOXES = {}
LOG = []
LOCK = Mutex.new

def original_password(email)
    chars = 'BCDFGHJKMNPQRSTVWXYZ23456789'.split('')
    sha2 = Digest::SHA256.new()
    sha2 << EMAIL_PASSWORD_SALT
    sha2 << email
    rng = Random.new(sha2.hexdigest.to_i(16))
    password = ''
    until password =~ /[a-z]/ && password =~ /[A-Z]/ && password =~ /[0-9]/ && password.include?('-')
        password = ''
        8.times { c = chars.sample(random: rng).dup; c.downcase! if [0, 1].sample(random: rng) == 1; password += c }
        password += '-'
        4.times { c = chars.sample(random: rng).dup; c.downcase! if [0, 1].sample(random: rng) == 1; password += c }
    end
    password
end

# tag, command and arguments of a client line: atoms, "quoted", (lists)
def parse_line(line)
    tokens = line.scan(/"(?:[^"\\]|\\.)*"|\([^)]*\)|[^\s()]+/).map do |t|
        t.start_with?('"') ? t[1..-2].gsub(/\\(.)/, '\1') : t
    end
    [tokens[0], (tokens[1] || '').upcase, tokens[2..] || []]
end

def quoted(text)
    '"' + text.gsub('\\', '\\\\\\').gsub('"', '\\"') + '"'
end

def imap_date(time)
    time.strftime('%d-%b-%Y %H:%M:%S %z')
end

def serve_imap(client)
    user = nil
    selected = nil
    client.write("* OK [CAPABILITY IMAP4rev1 QUOTA] fake IMAP ready\r\n")
    while (line = client.gets)
        tag, command, args = parse_line(line.chomp)
        break if tag.nil?
        LOCK.synchronize do
            LOG << {:user => user || (command == 'LOGIN' ? args[0] : nil), :command => command,
                    :args => command == 'LOGIN' ? [args[0]] : args}
        end
        mailbox = user && LOCK.synchronize { MAILBOXES[user] }
        case command
        when 'CAPABILITY'
            client.write("* CAPABILITY IMAP4rev1 QUOTA\r\n#{tag} OK CAPABILITY done\r\n")
        when 'NOOP'
            client.write("#{tag} OK NOOP done\r\n")
        when 'LOGIN'
            entry = LOCK.synchronize { MAILBOXES[args[0].to_s.downcase] }
            if entry && entry['accept'] == 'original' && args[1] == original_password(args[0].to_s.downcase)
                user = args[0].to_s.downcase
                client.write("#{tag} OK [CAPABILITY IMAP4rev1 QUOTA] LOGIN completed\r\n")
            else
                client.write("#{tag} NO [AUTHENTICATIONFAILED] Authentication failed\r\n")
            end
        when 'LOGOUT'
            client.write("* BYE logging out\r\n#{tag} OK LOGOUT completed\r\n")
            break
        else
            unless mailbox
                client.write("#{tag} BAD not logged in\r\n")
                next
            end
            folders = mailbox['folders'] || []
            folder = lambda { |name| folders.find { |f| f['name'] == name } }
            case command
            when 'LIST'
                folders.each { |f| client.write("* LIST (\\HasNoChildren) \"/\" #{quoted(f['name'])}\r\n") }
                client.write("#{tag} OK LIST completed\r\n")
            when 'STATUS'
                f = folder.call(args[0])
                if f
                    client.write("* STATUS #{quoted(f['name'])} (MESSAGES #{f['dates'].size})\r\n#{tag} OK STATUS completed\r\n")
                else
                    client.write("#{tag} NO no such folder\r\n")
                end
            when 'EXAMINE'
                selected = folder.call(args[0])
                if selected
                    client.write("* FLAGS (\\Seen)\r\n* #{selected['dates'].size} EXISTS\r\n* 0 RECENT\r\n#{tag} OK [READ-ONLY] EXAMINE completed\r\n")
                else
                    client.write("#{tag} NO no such folder\r\n")
                end
            when 'SEARCH'
                dates = (selected || {})['dates'] || []
                since = args[0].to_s.upcase == 'SINCE' ? Date.parse(args[1]) : nil
                found = dates.each_index.select { |i| since.nil? || Time.parse(dates[i]).to_date >= since }.map { |i| i + 1 }
                client.write("* SEARCH#{found.map { |i| " #{i}" }.join}\r\n#{tag} OK SEARCH completed\r\n")
            when 'FETCH'
                dates = (selected || {})['dates'] || []
                # nothing but the arrival time, and only of the newest mail
                if args[0] == '*' && args[1].to_s.upcase.delete('()') == 'INTERNALDATE' && !dates.empty?
                    client.write("* #{dates.size} FETCH (INTERNALDATE #{quoted(imap_date(Time.parse(dates.last)))})\r\n")
                    client.write("#{tag} OK FETCH completed\r\n")
                else
                    client.write("#{tag} NO only the newest INTERNALDATE is served\r\n")
                end
            when 'GETQUOTAROOT'
                quota = mailbox['quota']
                client.write("* QUOTAROOT #{quoted(args[0].to_s)} \"\"\r\n")
                # like the real server: storage and message count in one response
                client.write("* QUOTA \"\" (STORAGE #{quota['used_kb']} #{quota['limit_kb']} MESSAGE 0 100000)\r\n") if quota
                client.write("#{tag} OK GETQUOTAROOT completed\r\n")
            else
                client.write("#{tag} BAD unknown command\r\n")
            end
        end
    end
rescue IOError, SystemCallError
ensure
    client.close rescue nil
end

Thread.new do
    server = TCPServer.new('0.0.0.0', 1143)
    loop do
        client = server.accept
        Thread.new(client) { |c| serve_imap(c) }
    end
end

run lambda { |env|
    request = Rack::Request.new(env)
    if request.post? && request.path == '/_mailbox'
        data = JSON.parse(request.body.read)
        LOCK.synchronize { MAILBOXES[data['user'].to_s.downcase] = data }
        [200, {'content-type' => 'application/json'}, ['{"ok":true}']]
    elsif request.delete? && request.path == '/_mailboxes'
        LOCK.synchronize { MAILBOXES.clear; LOG.clear }
        [200, {'content-type' => 'application/json'}, ['{"ok":true}']]
    elsif request.get? && request.path == '/_log'
        [200, {'content-type' => 'application/json'}, [LOCK.synchronize { LOG.to_json }]]
    else
        [404, {'content-type' => 'text/plain'}, ['not found']]
    end
}
