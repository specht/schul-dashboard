#!/usr/bin/env ruby

require 'date'
require 'neo4j_bolt'
require 'set'
require 'xsv'
require 'yaml'
require 'securerandom'

include Neo4jBolt

Neo4jBolt.bolt_host = 'neo4j'
Neo4jBolt.bolt_port = 7687

user_info = YAML.load_file("/internal/debug/@@user_info.yaml", permitted_classes: [Symbol, Set])
shorthands = YAML.load_file("/internal/debug/@@shorthands.yaml")
schueler_for_klasse = YAML.load_file("/internal/debug/@@schueler_for_klasse.yaml")

class RandomTag
    BASE_31_ALPHABET = '0123456789bcdfghjklmnpqrstvwxyz'
    def self.to_base31(i)
        result = ''
        while i > 0
            result += BASE_31_ALPHABET[i % 31]
            i /= 31
        end
        result
    end

    def self.generate(length = 12)
        self.to_base31(SecureRandom.hex(length).to_i(16))[0, length]
    end
end

pk5_hash = {}
pk5_for_sus = {}
errors = []

neo4j_query(<<~END_OF_QUERY).each do |row|
    MATCH (p:Pk5)-[:BELONGS_TO]->(u:User)
    RETURN p, COLLECT(u.email) AS emails;
END_OF_QUERY
    p = row['p']
    emails = row['emails']
    emails.each do |email|
        unless schueler_for_klasse['12'].include?(email)
            raise "Schüler #{email} nicht in Klasse 12!"
        end
    end
    tag = RandomTag.generate(12)
    pk5_hash[tag] = {:pk5 => {
        :themengebiet => p[:themengebiet],
        :betreuende_lehrkraft => p[:betreuende_lehrkraft],
        :betreuende_lehrkraft_confirmed_by => p[:betreuende_lehrkraft_confirmed_by],
        :betreuende_lehrkraft_fas => p[:betreuende_lehrkraft_fas],
        :extra_consultations => p[:extra_consultations]
    }, :emails => emails}
    emails.each do |email|
        if pk5_for_sus[email]
            errors << sus
        end
        pk5_for_sus[email] = tag
    end
end

unless errors.empty?
    STDERR.puts "Duplicate Pk5 for: #{errors.join(', ')}"
    raise 'nope'
end

# Pro 5. PK: n Beratungstermine mit n Lehrkräften, 1 oder 2 SuS (gemeinsam)
# - alle Gespräche in einen Pott
# - zufällig ziehen, Lehrer und SuS müssen Zeit haben
# - Fehler berechnen
# - 1000 mal wiederholen, Fehler minimieren

pool = []

pk5_hash.each do |tag, data|
    teachers = []
    pk5 = data[:pk5]
    # add betreuende_lehrkraft_confirmed_by if it's the same as betreuende_lehrkraft
    if pk5[:betreuende_lehrkraft] && pk5[:betreuende_lehrkraft_confirmed_by] == pk5[:betreuende_lehrkraft]
        teachers << pk5[:betreuende_lehrkraft]
    end
    # add betreuende_lehrkraft_fas if set
    if pk5[:betreuende_lehrkraft_fas]
        teachers << pk5[:betreuende_lehrkraft_fas]
    end
    if pk5[:extra_consultations]
        pk5[:extra_consultations].split(',').each do |shorthand|
            teachers << shorthands[shorthand]
        end
    end

    teachers.uniq!

    teachers.each do |email|
        pool << {:teacher => email, :tag => tag, :duration => data[:emails].size == 1 ? 15 : 25}
    end
end

pool_copy = pool.to_yaml
# STDERR.puts pool_copy.to_yaml

min_error = nil
best_solution = nil
pk5_hash_copy = pk5_hash.to_yaml

# Info: a slot amount to 5 minutes

1000.times do
    pool = YAML.load(pool_copy)
    pk5_hash = YAML.load(pk5_hash_copy)
    # STDERR.puts "Scheduling #{pool.size} consultations."

    teacher_slots = {}
    pk5_slots = {}

    # puts pool.select { |x| x[:teacher] == 'frei@gymnasiumsteglitz.de'}.to_yaml
    # exit

    fail_count = 0
    while !pool.empty?
        # First round: stack teacher appointments and see whatever fits
        i = rand(pool.length)
        talk = pool[i]
        tag = talk[:tag]
        teacher = talk[:teacher]
        pk5 = pk5_hash[tag]
        slot_count = talk[:duration] / 5
        pool.delete_at(i)
        sus_emails = pk5[:emails]
        # STDERR.puts "#{teacher} + #{sus_emails.join(' + ')}"
        teacher_slots[teacher] ||= {}
        pk5_slots[tag] ||= {}
        candidates = (0..100).reject { |x| (0...slot_count).any? { |i| teacher_slots[teacher].include?(x + i) } }.sort
        slot = candidates.first
        if (0...slot_count).any? { |i| pk5_slots[tag].include?(slot + i) }
            # Error: slot is not available because Pk5 team is already in another talk
            # Put the item back
            fail_count += 1
            pool << talk
        else
            fail_count = 0
            (0...slot_count).each do |i|
                pk5_slots[tag][slot + i] = talk
                teacher_slots[teacher][slot + i] = talk
                pk5_hash[tag][:talks] ||= {}
                pk5_hash[tag][:talks][slot + i] = teacher
            end
        end
        break if fail_count > 1000
    end

    # STDERR.puts pk5_slots.to_yaml
    # exit

    # puts "#{pool.size} talks left to distribute"

    while !pool.empty?
        # Second round: pick up remaining talks, and find an appointment that
        # fits for everybody but might be late
        i = rand(pool.length)
        talk = pool[i]
        tag = talk[:tag]
        teacher = talk[:teacher]
        pk5 = pk5_hash[tag]
        slot_count = talk[:duration] / 5
        pool.delete_at(i)
        sus_emails = pk5[:emails]
        # STDERR.puts "#{teacher} + #{sus_emails.join(' + ')}"
        teacher_slots[teacher] ||= {}
        pk5_slots[tag] ||= {}
        candidates = (0..100).reject { |x| (0...slot_count).any? { |i| teacher_slots[teacher].include?(x + i) || pk5_slots[tag].include?(x + i)} }.sort
        slot = candidates.first
        if (0...slot_count).any? { |i| pk5_slots[tag].include?(slot + i) }
            raise 'This cannot happen, but it did.'
        else
            fail_count = 0
            (0...slot_count).each do |i|
                pk5_slots[tag][slot + i] = talk
                teacher_slots[teacher][slot + i] = talk
                pk5_hash[tag][:talks] ||= {}
                pk5_hash[tag][:talks][slot + i] = teacher
            end
        end
    end

    # puts 'done'

    # puts pk5_hash.to_yaml
    error = 0
    teacher_slots.each_pair do |email, data|
        slots = data.keys.sort
        error += slots.last + 1 - slots.size
    end
    # puts teacher_slots.to_yaml
    min_error ||= error
    best_solution ||= pk5_hash.to_yaml
    if error < min_error
        puts "Found new best solution with error #{error}"
        min_error = error
        best_solution = pk5_hash.to_yaml
    end
end

path = "/internal/schedule-beratungstermine-out-error-#{min_error}.yaml"
File.open(path, 'w') do |f|
    f.write best_solution
end

puts "Wrote results with error #{min_error} to '#{path}', now call schedule-beratungstermine-create-termine.rb."