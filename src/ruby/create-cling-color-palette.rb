#!/usr/bin/env ruby

require 'json'
require 'yaml'

CLING_COLORS = [
  ["#ffe617", "daffodil"],
  ["#fad31c", "daisy"],
  ["#fdb717", "mustard"],
  ["#faaa21", "circus zest"],
  ["#f1753f", "pumpkin"],
  ["#ed5724", "tangerine"],
  ["#ef4538", "salmon"],
  ["#ea2830", "persimmon"],
  ["#bc2326", "rouge"],
  ["#8c0c03", "scarlet"],
  ["#e5185d", "hot pink"],

  ["#f384ae", "princess"],
  ["#fac6d2", "petal"],
  ["#b296c7", "lilac"],
  ["#7b67ae", "lavender"],
  ["#5f3577", "violet"],

  ["#c1d18a", "ceadon"],
  ["#799155", "olive"],
  ["#80bc42", "bamboo"],
  ["#4aa03f", "grass"],
  ["#16884a", "kelly"],
  ["#003f2e", "forrest"],

  ["#c3def1", "cloud"],
  ["#55beed", "dream"],
  ["#31a8e0", "gulf"],
  ["#238acc", "turquoise"],
  ["#0d60ae", "sky"],
  ["#143b86", "indigo"],
  ["#001b4a", "navy"],
  ["#7dcdc2", "sea foam"],
  ["#00a8a8", "teal"],
  ["#12959f", "peacock"],
  ["#094e54", "cyan"],

  ["#381e11", "chocolate"],
  ["#c05c20", "terra cotta"],
  ["#bf9b6b", "camel"],
  ["#e9d4a7", "linen"],
  ["#e7e6e1", "stone"],
  ["#cfd0d2", "smoke"],
  ["#8a8b8f", "steel"],
  ["#778590", "slate"],
  ["#474d4d", "charcoal"],
  ["#050608", "black"],
  ["#ffffff", "white"],
]

def hsv_to_rgb(c)
    h, s, v = c[0].to_f / 360, c[1].to_f / 100, c[2].to_f / 100
    h_i = (h * 6).to_i
    f = h * 6 - h_i
    p = v * (1 - s)
    q = v * (1 - f * s)
    t = v * (1 - (1 - f) * s)
    r, g, b = v, t, p if h_i == 0
    r, g, b = q, v, p if h_i == 1
    r, g, b = p, v, t if h_i == 2
    r, g, b = p, q, v if h_i == 3
    r, g, b = t, p, v if h_i == 4
    r, g, b = v, p, q if h_i == 5
    [(r * 255).to_i, (g * 255).to_i, (b * 255).to_i]
end


# http://ntlk.net/2011/11/21/convert-rgb-to-hsb-hsv-in-ruby/
def rgb_to_hsv(c)
    r = c[0] / 255.0
    g = c[1] / 255.0
    b = c[2] / 255.0
    max = [r, g, b].max
    min = [r, g, b].min
    delta = max - min
    v = max * 100

    if (max != 0.0)
        s = delta / max *100
    else
        s = 0.0
    end

    if (s == 0.0)
        h = 0.0
    else
        if (r == max)
            h = (g - b) / delta
        elsif (g == max)
            h = 2 + (b - r) / delta
        elsif (b == max)
            h = 4 + (r - g) / delta
        end

        h *= 60.0

        if (h < 0)
            h += 360.0
        end
    end
    [h, s, v]
end

def hex_to_rgb(c)
    r = c[1, 2].downcase.to_i(16)
    g = c[3, 2].downcase.to_i(16)
    b = c[5, 2].downcase.to_i(16)
    [r, g, b]
end

def luminance(color) 
    r, g, b = hex_to_rgb(color)
    return r * 0.299 + g * 0.587 + b * 0.114
end

def mix(a, b, t)
    t1 = 1.0 - t
    return [a[0] * t1 + b[0] * t,
            a[1] * t1 + b[1] * t,
            a[2] * t1 + b[2] * t]
end

def rgb_to_hex(c)
    sprintf('#%02x%02x%02x', c[0].to_i, c[1].to_i, c[2].to_i)
end

def desaturate(c)
    hsv = rgb_to_hsv(hex_to_rgb(c))
    hsv[1] *= 0.7
    hsv[2] *= 0.9
    rgb_to_hex(hsv_to_rgb(hsv))
end

def shift_hue(c, f = 60)
    hsv = rgb_to_hsv(hex_to_rgb(c))
    hsv[0] = (hsv[0] + f) % 360.0
    rgb_to_hex(hsv_to_rgb(hsv))
end

def darken(c, f = 0.2)
    hsv = rgb_to_hsv(hex_to_rgb(c))
    hsv[2] *= f
    rgb_to_hex(hsv_to_rgb(hsv))
end

def html_to_rgb(x)
    [x[1, 2].to_i(16), x[3, 2].to_i(16), x[5, 2].to_i(16)]
end

def rgb_to_html(x)
    sprintf('#%02x%02x%02x', x[0], x[1], x[2])
end

def get_gradient(colors, t)
    i = (t * (colors.size - 1)).to_i
    i = colors.size - 2 if i == colors.size - 1
    f = (t * (colors.size - 1)) - i
    f1 = 1.0 - f
    a = html_to_rgb(colors[i])
    b = html_to_rgb(colors[i + 1])
    rgb_to_html([a[0] * f1 + b[0] * f, a[1] * f1 + b[1] * f, a[2] * f1 + b[2] * f])
end

def color_palette_for_color_scheme(color_scheme)
    primary_color = '#' + color_scheme[7, 6]
    light = luminance(primary_color) > 160
    primary_color_darker = darken(primary_color, 0.8)
    desaturated_color = darken(desaturate(primary_color), 0.9)
    if light
        desaturated_color = rgb_to_hex(mix(hex_to_rgb(desaturate(primary_color)), hex_to_rgb('#ffffff'), 0.1))
    end
    desaturated_color_darker = darken(desaturate(primary_color), 0.3)
    disabled_color = light ? rgb_to_hex(mix(hex_to_rgb(primary_color), [255, 255, 255], 0.5)) : rgb_to_hex(mix(hex_to_rgb(primary_color), [192, 192, 192], 0.5))
    darker_color = rgb_to_hex(mix(hex_to_rgb(primary_color), [0, 0, 0], 0.6))
    shifted_color = shift_hue(primary_color, 350)
    main_text_color = light ? rgb_to_hex(mix(hex_to_rgb(primary_color), [0, 0, 0], 0.7)) : rgb_to_hex(mix(hex_to_rgb(primary_color), [255, 255, 255], 0.8))
    contrast_color = rgb_to_hex(mix(hex_to_rgb(primary_color), color_scheme[0] == 'l' ? [0, 0, 0] : [255, 255, 255], 0.7))
    color_palette = {
        :is_light => light,
        :primary => primary_color, 
        :primary_color_darker => primary_color_darker,
        :disabled => disabled_color, 
        :darker => darker_color, 
        :shifted => desaturated_color,
        :left => '#' + color_scheme[1, 6],
        :right => '#' + color_scheme[13, 6],
        :main_text => main_text_color,
        :contrast => contrast_color
    }
    color_palette
end

File.open('cling-colors.html', 'w') do |f|
    f.puts "<html>"
    f.puts "<head>"
    f.puts "<style>"
    f.puts "body { font-family: monospace; font-size: 10pt; }"
    f.puts ".name { display: inline-block; width: 8em; }"
    f.puts ".swatch { display: inline-block; text-align: center; padding: 0.5em 1em;}"
    colors = {}
    CLING_COLORS.each do |entry|
        hex = entry[0]
        name = entry[1].gsub(' ', '-')
        tints = []
        dark = mix(hex_to_rgb(hex), hex_to_rgb('#000000'), 0.85)
        (0...4).each do |i|
            tints << rgb_to_hex(mix(dark, hex_to_rgb(hex), (i.to_f / 4) ** 1.5))
        end
        tints << hex
        light = mix(hex_to_rgb(hex), hex_to_rgb('#ffffff'), 0.8)
        (0...4).each do |i|
            tints << rgb_to_hex(mix(light, hex_to_rgb(hex), (3 - i).to_f / 4))
        end
        tints.each.with_index do |c, i|
            f.puts ".text-#{name}-#{(i + 1) * 100}{color:#{c};}.bg-#{name}-#{(i + 1) * 100}{background-color:#{c};}"
            colors["#{name}-#{(i + 1) * 100}"] = c
        end
    end
    f.puts "</style>"
    f.puts "<script>"
    f.puts "var CLING_COLORS = #{colors.to_json};"
    f.puts "</script>"
    f.puts "</head>"
    f.puts "<body>"
    CLING_COLORS.each do |entry|
        name = entry[1].gsub(' ', '-')
        f.puts "<span class='name'>#{name}</span>"
        (1..9).each do |i|
            f.print "<span class='swatch bg-#{name}-#{i * 100}'>#{i*100}</span>"
        end
        f.puts "<br />"
    end
    f.puts "</body>"
    f.puts "</html>"
end
