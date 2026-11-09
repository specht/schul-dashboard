require 'date'

# A/B weeks (SWITCH_WEEKS: {'2023-08-28' => ['A', 2], …} – from that Monday on,
# weeks alternate starting with A). Counts the weeks since the reference
# Monday: the difference of ISO week numbers went wrong after years with 53
# weeks (2026: 28 December and 4 January 2027 would both have been A).
module SwitchWeeks
    def self.letter(date, switch_weeks)
        ds = date.strftime('%Y-%m-%d')
        since = switch_weeks.keys.sort.select { |d| ds >= d }.last
        info = switch_weeks[since]
        return nil if info.nil?
        start = Date.parse(since)
        monday = ->(d) { d - (d.cwday - 1) }
        weeks = (monday.call(date) - monday.call(start)).to_i / 7
        (((weeks + (info[0].ord - 'A'.ord)) % info[1]) + 'A'.ord).chr
    end
end
