#!/usr/bin/env ruby
# Compares two sets of rendered pages from the page smoke test
# (SAVE_PAGES_DIR, see test/e2e/tests/pages.smoke.ts), e.g. before and after
# a change of the template renderer. Values that change on every request
# (timestamps, random choices) are normalized first.
#
#   ruby test/compare_pages.rb test/e2e/golden/before test/e2e/golden/after
#
# Prints the pages that differ (with the first differing lines) and exits
# with 1 if there are any.

a_dir, b_dir = ARGV
abort "usage: #{$0} <dir a> <dir b>" unless a_dir && b_dir && File.directory?(a_dir) && File.directory?(b_dir)

NORMALIZE = [
    [/(show_messages_from = )\d+/, '\1<ts>'],
    [/(\.js\?)\d{9,}/, '\1<ts>'],
    # deadline for the second factor counts from the first login on this stack
    [/(Hinterlegung des zweiten Faktors endet am <strong>)[^<]*(<\/strong> um <strong>)[^<]*/, '\1<date>\2<time>'],
]

# Pages whose content changes between two runs of the same version (every
# run logs in again, statistics count, games are random). Listed separately:
# look at their differences by hand.
VARYING = %w(admin.html profil.html stats.html inactive_sus.html cyph3r.html h4ck.html maze.html)

def normalized(path)
    s = File.read(path, encoding: 'utf-8').scrub
    NORMALIZE.each { |pattern, replacement| s = s.gsub(pattern, replacement) }
    s
end

files = (Dir.glob('**/*.html', base: a_dir) + Dir.glob('**/*.html', base: b_dir)).uniq.sort
different = []
files.each do |file|
    a = File.join(a_dir, file)
    b = File.join(b_dir, file)
    unless File.exist?(a) && File.exist?(b)
        different << [file, ['only in one of the two sets']]
        next
    end
    la = normalized(a).lines
    lb = normalized(b).lines
    next if la == lb
    lines = []
    [la.size, lb.size].max.times do |i|
        next if la[i] == lb[i]
        lines << "#{i + 1}: - #{(la[i] || '').strip[0, 150]}"
        lines << "#{i + 1}: + #{(lb[i] || '').strip[0, 150]}"
        break if lines.size >= 6
    end
    different << [file, lines]
end

varying, strict = different.partition { |file, _| VARYING.include?(File.basename(file)) }
strict.each do |file, lines|
    puts file
    lines.each { |l| puts "    #{l}" }
end
puts "#{strict.size} of #{files.size} pages differ"
puts "(#{varying.size} differences on pages that vary by themselves, check by hand: #{varying.map(&:first).join(' ')})" unless varying.empty?
exit(strict.empty? ? 0 : 1)
