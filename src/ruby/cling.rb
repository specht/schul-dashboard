# The Cling palette (http://clingeverything.com/color-palette; as in the
# Hackschule sprite editor, github.com/specht/2d palettes/cling.txt) without
# black and white, which are weak as colours of their own: 42 colours with
# German names. One's own colour scheme (profile) and the colours of the
# lesson mails (/unterrichtsmails) are picked from it.
module Cling
    COLOURS = [
        ['#ffe617', 'Narzisse'], ['#fad31c', 'Sonnengelb'], ['#fdb717', 'Senf'],
        ['#faaa21', 'Zirkusorange'], ['#f1753f', 'Kürbis'], ['#ed5724', 'Mandarine'],
        ['#ef4538', 'Lachs'], ['#ea2830', 'Kaki'], ['#bc2326', 'Rubin'],
        ['#8c0c03', 'Scharlach'], ['#e5185d', 'Pink'], ['#f384ae', 'Rosa'],
        ['#fac6d2', 'Zartrosa'], ['#b296c7', 'Flieder'], ['#7b67ae', 'Lavendel'],
        ['#5f3577', 'Violett'], ['#c1d18a', 'Seladon'], ['#799155', 'Olive'],
        ['#80bc42', 'Bambus'], ['#4aa03f', 'Gras'], ['#16884a', 'Kleegrün'],
        ['#003f2e', 'Wald'], ['#c3def1', 'Wolke'], ['#55beed', 'Traumblau'],
        ['#31a8e0', 'Golf'], ['#238acc', 'Azur'], ['#0d60ae', 'Himmel'],
        ['#143b86', 'Indigo'], ['#001b4a', 'Marine'], ['#7dcdc2', 'Meerschaum'],
        ['#00a8a8', 'Blaugrün'], ['#12959f', 'Pfau'], ['#094e54', 'Tiefsee'],
        ['#381e11', 'Schokolade'], ['#c05c20', 'Terrakotta'], ['#bf9b6b', 'Kamel'],
        ['#e9d4a7', 'Leinen'], ['#e7e6e1', 'Stein'], ['#cfd0d2', 'Rauch'],
        ['#8a8b8f', 'Stahl'], ['#778590', 'Schiefer'], ['#474d4d', 'Anthrazit'],
    ].map { |hex, name| [hex.freeze, name.freeze].freeze }.freeze
    HEXES = COLOURS.map(&:first).freeze

    def self.include?(hex)
        HEXES.include?(hex.to_s.downcase)
    end

    def self.rgb(hex)
        hex[1, 6].scan(/../).map { |x| x.to_i(16) }
    end

    # the palette colour closest to any colour (the »redmean« distance, close
    # to what the eye sees); nil for something that is no colour
    def self.nearest(hex)
        return nil unless hex.to_s =~ /\A#[0-9a-fA-F]{6}\z/
        a = rgb(hex.downcase)
        HEXES.min_by do |h|
            b = rgb(h)
            rm = (a[0] + b[0]) / 2.0
            (2 + rm / 256) * (a[0] - b[0])**2 + 4 * (a[1] - b[1])**2 + (2 + (255 - rm) / 256) * (a[2] - b[2])**2
        end
    end

    # light colours get dark writing (a check mark, a label), dark ones white
    def self.light?(hex)
        r, g, b = rgb(hex).map { |x| x / 255.0 }
        0.299 * r + 0.587 * g + 0.114 * b > 0.6
    end
end
