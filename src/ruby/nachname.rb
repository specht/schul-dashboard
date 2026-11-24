# Name particles (von, de, van der, …) – one rule for the whole dashboard:
#
# - kept behind the name, »Hofe, von«: so the student lists always had them
#   (sorted under the name, like LUSD's own lists), and every list is read
#   that way, whatever form it came in (LUSD writes »von Hofe«);
# - shown in front, »von Hofe«: in the dashboard, on lists to check, in the
#   addresses (Parser#name_to_display_name, #name_to_email);
# - compared in the kept form, so »von Hofe« and »Hofe, von« are the same.
module Nachname
    # the form the lists keep: leading lower-case words are the particle
    def self.intern(name)
        n = name.to_s.strip.gsub(/\s+/, ' ')
        return n.split(',', 2).map(&:strip).reject(&:empty?).join(', ') if n.include?(',')
        words = n.split(' ')
        i = 0
        i += 1 while i < words.size - 1 && words[i] =~ /\A\p{Ll}/
        return n if i == 0
        "#{words[i..].join(' ')}, #{words[0...i].join(' ')}"
    end

    # the form to show
    def self.anzeige(name)
        n = name.to_s.strip
        return n unless n.include?(',')
        teile = n.split(',', 2).map(&:strip)
        "#{teile[1]} #{teile[0]}".strip
    end
end
