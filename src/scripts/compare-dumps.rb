#!/usr/bin/env ruby
# Compares two neo4j_bolt dumps by content, independent of the dump-local IDs.
# A node is identified by its labels and properties plus the multiset of its
# relationships (type, properties, direction) and their end nodes' content, so
# that e.g. two copies with the same bnr but of different books stay
# distinguishable. A relationship is identified by its type, properties and the
# identities of both end nodes.
#
#   src/scripts/compare-dumps.rb A.txt B.txt   # exit 0 if the data is identical
#   src/scripts/compare-dumps.rb --check A.txt # only check A for consistency
#
# Schema records (u/k/i, written by neo4j_bolt >= 0.4) are listed but do not
# count as a difference, because dumps made with neo4j_bolt 0.3 have none.
#
# Taken over from gyst-bib for the Neo4j 5 migration
# (review/2026-11/neo4j-5-migration.md). Differences are reported without
# property values – the dumps hold personal data –, only with labels,
# relationship types and property keys.

require 'digest'
require 'json'

def canonical(value)
    case value
    when Hash then value.keys.sort.map { |k| [k, canonical(value[k])] }
    when Array then value.map { |x| canonical(x) }
    else value
    end
end

def read_dump(path)
    node_key = {}
    raw_rels = []
    node_counts = Hash.new(0)
    rel_counts = Hash.new(0)
    schema = []
    errors = []
    File.open(path) do |f|
        f.each_line.with_index do |line, i|
            line = line.strip
            next if line.empty?
            kind, json = line.split(' ', 2)
            begin
                data = JSON.parse(json)
            rescue StandardError => e
                errors << "line #{i + 1}: #{e.message}"
                next
            end
            case kind
            when 'n'
                key = JSON.generate([data['labels'].sort, canonical(data['properties'] || {})])
                errors << "line #{i + 1}: duplicate node id #{data['id']}" if node_key.include?(data['id'])
                node_key[data['id']] = key
                node_counts[data['labels'].sort.join(':')] += 1
            when 'r'
                unless node_key.include?(data['from']) && node_key.include?(data['to'])
                    errors << "line #{i + 1}: #{data['type']} relationship refers to a missing node (from #{data['from'].inspect}, to #{data['to'].inspect})"
                    next
                end
                raw_rels << [data['type'], JSON.generate(canonical(data['properties'] || {})), data['from'], data['to']]
                rel_counts[data['type']] += 1
            when 'u', 'k', 'i'
                schema << "#{kind} #{JSON.generate(canonical(data))}"
            else
                errors << "line #{i + 1}: unknown record type #{kind.inspect}"
            end
        end
    end
    # one round of neighbourhood refinement
    signature = Hash.new { |h, k| h[k] = [] }
    raw_rels.each do |type, props, from, to|
        signature[from] << "out #{type} #{props} #{node_key[to]}"
        signature[to] << "in #{type} #{props} #{node_key[from]}"
    end
    refined = {}
    node_key.each_pair do |id, key|
        refined[id] = Digest::SHA1.hexdigest(key + "\n" + signature[id].sort.join("\n"))
    end
    nodes = Hash.new(0)
    node_key.each_pair { |id, key| nodes["#{key} ##{refined[id][0, 8]}"] += 1 }
    rels = Hash.new(0)
    raw_rels.each do |type, props, from, to|
        rels["#{type} #{props} #{node_key[from]} ##{refined[from][0, 8]} -> #{node_key[to]} ##{refined[to][0, 8]}"] += 1
    end
    {
        :nodes => nodes, :rels => rels, :node_counts => node_counts,
        :rel_counts => rel_counts, :schema => schema.sort, :errors => errors
    }
end

# a node or relationship variant without values: labels/type and property keys
def describe(entry)
    if entry =~ /\A(\[.*?\]) #/
        labels, props = JSON.parse($1)
        "(:#{labels.join(':')} {#{props.map(&:first).join(', ')}})"
    else
        type, props = entry.split(' ', 3)
        keys = (JSON.parse(props) rescue []).map(&:first)
        "[:#{type} {#{keys.join(', ')}}]"
    end
end

def multiset_diff(a, b)
    (a.keys | b.keys).each_with_object([]) do |key, out|
        d = (a[key] || 0) - (b[key] || 0)
        out << [key, d] if d != 0
    end
end

def print_errors(path, dump)
    return if dump[:errors].empty?
    puts "#{path}: #{dump[:errors].size} consistency error(s):"
    dump[:errors].first(10).each { |e| puts "  #{e}" }
end

if ARGV.first == '--check'
    path = ARGV[1] or abort "usage: #{$0} --check DUMP"
    dump = read_dump(path)
    puts "#{path}: #{dump[:node_counts].values.sum} nodes, #{dump[:rel_counts].values.sum} relationships, #{dump[:schema].size} schema records"
    print_errors(path, dump)
    exit(dump[:errors].empty? ? 0 : 1)
end

abort "usage: #{$0} A B  |  #{$0} --check A" unless ARGV.size == 2
a_path, b_path = ARGV
a = read_dump(a_path)
b = read_dump(b_path)

ok = a[:errors].empty? && b[:errors].empty?
print_errors(a_path, a)
print_errors(b_path, b)

puts format('%-24s %10s %10s', 'nodes / relationships', 'A', 'B')
[[:node_counts, '(:%s)'], [:rel_counts, '[:%s]']].each do |key, fmt|
    (a[key].keys | b[key].keys).sort.each do |name|
        mark = a[key][name] == b[key][name] ? '' : '   <-- differs'
        puts format("%-24s %10d %10d%s", format(fmt, name), a[key][name], b[key][name], mark)
    end
end

[[:nodes, 'node'], [:rels, 'relationship']].each do |key, what|
    diff = multiset_diff(a[key], b[key])
    next if diff.empty?
    ok = false
    puts "#{diff.size} #{what} variant(s) differ in content, for example:"
    diff.first(5).each do |entry, d|
        puts "  #{d > 0 ? "only in A (x#{d})" : "only in B (x#{-d})"}: #{describe(entry)}"
    end
end

if a[:schema] != b[:schema]
    puts "Schema records differ (not counted as a data difference):"
    puts "  A: #{a[:schema].size} record(s), B: #{b[:schema].size} record(s)"
    (a[:schema] - b[:schema]).each { |s| puts "  only in A: #{s[0, 200]}" }
    (b[:schema] - a[:schema]).each { |s| puts "  only in B: #{s[0, 200]}" }
end

puts ok ? 'RESULT: the data in both dumps is identical.' : 'RESULT: the dumps differ.'
exit(ok ? 0 : 1)
