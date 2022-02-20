require 'fileutils'

BASE62_ALPHABET = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')

def i_to_b62(n)
    s = ''
    while n > 0
        d = n % 62
        s = BASE62_ALPHABET[d] + s
        n /= 62
    end
    s
end

class BackgroundRenderer
    # http://martin.ankerl.com/2009/12/09/how-to-create-random-colors-programmatically
    def hsv_to_rgb(c)
        h, s, v = c[0].to_f/360, c[1].to_f/100, c[2].to_f/100
        h_i = (h*6).to_i
        f = h*6 - h_i
        p = v * (1 - s)
        q = v * (1 - f*s)
        t = v * (1 - (1 - f) * s)
        r, g, b = v, t, p if h_i==0
        r, g, b = q, v, p if h_i==1
        r, g, b = p, v, t if h_i==2
        r, g, b = p, q, v if h_i==3
        r, g, b = t, p, v if h_i==4
        r, g, b = v, p, q if h_i==5
        [(r*255).to_i, (g*255).to_i, (b*255).to_i]
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

    def mix(a, b, t)
        t1 = 1.0 - t
        return [a[0] * t1 + b[0] * t,
                a[1] * t1 + b[1] * t,
                a[2] * t1 + b[2] * t]
    end

    def rgb_to_hex(c)
        sprintf('#%02x%02x%02x', c[0].to_i, c[1].to_i, c[2].to_i)
    end

    def draw_triangle(f, g, p0, p1, p2, m, ld_mode, classes, lines)
        x0 = p0[0]; y0 = p0[1]
        x1 = p1[0]; y1 = p1[1]
        x2 = p2[0]; y2 = p2[1]
        mx = (x0 + x1 + x2) / 3.0
        my = (y0 + y1 + y2) / 3.0
        
        tx = mx / 1920.0
        ix = (tx * (g.size - 1)).to_i
        ix = g.size - 2 if ix >= g.size - 1
        ix = 0 if ix < 0
        ix = g.size - 1 if ix >= g.size - 1
        fx = tx * (g.size - 1) - ix
        fx = 0.0 if fx < 0.0
        fx = 1.0 if fx > 1.0
        
        fy = my / 1540.0
#         fy = fy * 0.8 + 0.2
        fy = 0.0 if fy < 0.0
        fy = 1.0 if fy > 1.0
        fy = 3 * fy ** 2 - 2 * fy ** 3
        
        bg_color = ld_mode == 'l' ? [248, 248, 248] : [8, 8, 8]
        # mix RGB
        color = rgb_to_hex(mix(mix(hex_to_rgb(g[ix]), hex_to_rgb(g[ix + 1]), fx), bg_color, fy))
        # mix HSV
#         color = rgb_to_hex(mix(hsv_to_rgb(mix(rgb_to_hsv(hex_to_rgb(g[ix])), rgb_to_hsv(hex_to_rgb(g[ix + 1])), fx)), bg_color, fy))
        if m == 0
            c1 = 'fill:none;stroke-width:2px;'
            c2 = "stroke:#{color}"
#             c2 = "stroke:#000"
            classes[c1] ||= i_to_b62(classes.size)
            classes[c2] ||= i_to_b62(classes.size)
            lines << "<path d='M #{x0.to_i},#{y0.to_i} #{x1.to_i},#{y1.to_i} #{x2.to_i},#{y2.to_i} Z' class='c#{classes[c1]} c#{classes[c2]}' />"
        else
            c1 = 'stroke:none;'
            c2 = "fill:rgba(0,0,0,#{sprintf('%1.3f', (1.0 - fy) * 0.2)}); filter:url(#blur);"
            classes[c1] ||= i_to_b62(classes.size)
            classes[c2] ||= i_to_b62(classes.size)
            lines << "<path d='M #{x0.to_i},#{y0.to_i} #{x1.to_i},#{y1.to_i} #{x2.to_i},#{y2.to_i} Z' class='c#{classes[c1]} c#{classes[c2]}' />"
            c1 = 'stroke:none;'
            c2 = "fill:#{color}"
            classes[c1] ||= i_to_b62(classes.size)
            classes[c2] ||= i_to_b62(classes.size)
            lines << "<path d='M #{x0.to_i},#{y0.to_i} #{x1.to_i},#{y1.to_i} #{x2.to_i},#{y2.to_i} Z' class='c#{classes[c1]} c#{classes[c2]}' />"
        end
    end
    
    def draw_curved_triangle(f, g, p0, p1, p2, p4, p5, p6, p7, p8, p3, m, ld_mode, shadow, curvy, classes, lines)
        x0 = p0[0]; y0 = p0[1]
        x1 = p1[0]; y1 = p1[1]
        x2 = p2[0]; y2 = p2[1]
        mx = (x0 + x1 + x2) / 3.0
        my = (y0 + y1 + y2) / 3.0
        t0 = 0.0
        t0 = 0.2 if curvy
#         t0 = 0.4
#         t0 = 0.6
#         t0 = 0.8
        t1 = 1.0 - t0
        p9 = [p6[0] * t0 + p0[0] * t1, p6[1] * t0 + p0[1] * t1]
        pa = [p3[0] * t0 + p1[0] * t1, p3[1] * t0 + p1[1] * t1]
        pb = [p8[0] * t0 + p1[0] * t1, p8[1] * t0 + p1[1] * t1]
        pc = [p5[0] * t0 + p2[0] * t1, p5[1] * t0 + p2[1] * t1]
        pd = [p4[0] * t0 + p2[0] * t1, p4[1] * t0 + p2[1] * t1]
        pe = [p7[0] * t0 + p0[0] * t1, p7[1] * t0 + p0[1] * t1]
        
        tx = mx / 1920.0
        ix = (tx * (g.size - 1)).to_i
        ix = g.size - 2 if ix >= g.size - 1
        ix = 0 if ix < 0
        ix = g.size - 1 if ix >= g.size - 1
        fx = tx * (g.size - 1) - ix
        fx = 0.0 if fx < 0.0
        fx = 1.0 if fx > 1.0
        
        fy = my / 1540.0
#         fy = fy * 0.8 + 0.2
        fy = 0.0 if fy < 0.0
        fy = 1.0 if fy > 1.0
        fy = 3 * fy ** 2 - 2 * fy ** 3
        
        bg_color = ld_mode == 'l' ? [248, 248, 248] : [8, 8, 8]
        # mix RGB
        color = rgb_to_hex(mix(mix(hex_to_rgb(g[ix]), hex_to_rgb(g[ix + 1]), fx), bg_color, fy))
        # mix HSV
#         color = rgb_to_hex(mix(hsv_to_rgb(mix(rgb_to_hsv(hex_to_rgb(g[ix])), rgb_to_hsv(hex_to_rgb(g[ix + 1])), fx)), bg_color, fy))
#         lines << "<circle cx='#{p3[0].to_i}' cy='#{p3[1].to_i}' r='5px' style='fill: #000;'/>"
#         lines << "<circle cx='#{p4[0].to_i}' cy='#{p4[1].to_i}' r='5px' style='fill: #f00;'/>"
#         lines << "<circle cx='#{p5[0].to_i}' cy='#{p5[1].to_i}' r='5px' style='fill: #0f0;'/>"
#         lines << "<circle cx='#{p6[0].to_i}' cy='#{p6[1].to_i}' r='5px' style='fill: #00f;'/>"
#         lines << "<circle cx='#{p7[0].to_i}' cy='#{p7[1].to_i}' r='5px' style='fill: #ff0;'/>"
#         lines << "<circle cx='#{p8[0].to_i}' cy='#{p8[1].to_i}' r='5px' style='fill: #0ff;'/>"
        if m == 0
            c1 = 'fill:none;stroke-width:2px;'
            c2 = "stroke:#{color}"
#             c2 = "stroke:#000"
            classes[c1] ||= i_to_b62(classes.size)
            classes[c2] ||= i_to_b62(classes.size)
#             lines << "<path d='M #{x0.to_i},#{y0.to_i} #{x1.to_i},#{y1.to_i} #{x2.to_i},#{y2.to_i} Z' class='c#{classes[c1]} c#{classes[c2]}' />"
#             lines << "<path d='M #{p3[0].to_i} #{p3[1].to_i} L#{p0[0].to_i} #{p0[1].to_i},#{p1[0].to_i} #{p1[1].to_i}, #{p6[0].to_i} #{p6[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
#             lines << "<path d='M #{p5[0].to_i} #{p5[1].to_i} L#{p1[0].to_i} #{p1[1].to_i},#{p2[0].to_i} #{p2[1].to_i}, #{p8[0].to_i} #{p8[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
#             lines << "<path d='M #{p4[0].to_i} #{p4[1].to_i} L#{p0[0].to_i} #{p0[1].to_i},#{p2[0].to_i} #{p2[1].to_i}, #{p7[0].to_i} #{p7[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
#             lines << "<path d='M #{p0[0].to_i} #{p0[1].to_i} L#{p9[0].to_i} #{p9[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
#             lines << "<path d='M #{p1[0].to_i} #{p1[1].to_i} L#{pa[0].to_i} #{pa[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
#             lines << "<path d='M #{p1[0].to_i} #{p1[1].to_i} L#{pb[0].to_i} #{pb[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
#             lines << "<path d='M #{p2[0].to_i} #{p2[1].to_i} L#{pc[0].to_i} #{pc[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
#             lines << "<path d='M #{p2[0].to_i} #{p2[1].to_i} L#{pd[0].to_i} #{pd[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
#             lines << "<path d='M #{p0[0].to_i} #{p0[1].to_i} L#{pe[0].to_i} #{pe[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
            lines << "<path d='M #{p0[0].to_i} #{p0[1].to_i} C#{p9[0].to_i} #{p9[1].to_i},#{pa[0].to_i} #{pa[1].to_i}, #{p1[0].to_i} #{p1[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
            lines << "<path d='M #{p1[0].to_i} #{p1[1].to_i} C#{pb[0].to_i} #{pb[1].to_i},#{pc[0].to_i} #{pc[1].to_i}, #{p2[0].to_i} #{p2[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
            lines << "<path d='M #{p2[0].to_i} #{p2[1].to_i} C#{pd[0].to_i} #{pd[1].to_i},#{pe[0].to_i} #{pe[1].to_i}, #{p0[0].to_i} #{p0[1].to_i}' class='c#{classes[c1]} c#{classes[c2]}' />"
        else
            if shadow == 1
                c1 = 'stroke:none;'
                c2 = "fill:#000; fill-opacity:#{sprintf('%1.3f', (1.0 - fy) * (ld_mode == 'l' ? 0.3 : 0.6))}; filter:url(#blur);"
                classes[c1] ||= i_to_b62(classes.size)
                classes[c2] ||= i_to_b62(classes.size)
                lines << "<path d='M #{p0[0].to_i} #{p0[1].to_i} C#{p9[0].to_i} #{p9[1].to_i},#{pa[0].to_i} #{pa[1].to_i}, #{p1[0].to_i} #{p1[1].to_i}, #{pb[0].to_i} #{pb[1].to_i},#{pc[0].to_i} #{pc[1].to_i}, #{p2[0].to_i} #{p2[1].to_i}, #{pd[0].to_i} #{pd[1].to_i},#{pe[0].to_i} #{pe[1].to_i}, #{p0[0].to_i} #{p0[1].to_i} Z' class='c#{classes[c1]} c#{classes[c2]}' />"
            end
            c1 = 'stroke:none;'
            c2 = "fill:#{color}"
            classes[c1] ||= i_to_b62(classes.size)
            classes[c2] ||= i_to_b62(classes.size)
            lines << "<path d='M #{p0[0].to_i} #{p0[1].to_i} C#{p9[0].to_i} #{p9[1].to_i},#{pa[0].to_i} #{pa[1].to_i}, #{p1[0].to_i} #{p1[1].to_i}, #{pb[0].to_i} #{pb[1].to_i},#{pc[0].to_i} #{pc[1].to_i}, #{p2[0].to_i} #{p2[1].to_i}, #{pd[0].to_i} #{pd[1].to_i},#{pe[0].to_i} #{pe[1].to_i}, #{p0[0].to_i} #{p0[1].to_i} Z' class='c#{classes[c1]} c#{classes[c2]}' />"
        end
    end
    
    def draw_circle(f, g, p0, p1, p2, m, ld_mode, classes, lines, randomize, r0, alpha, dx, dy, dr)
        if randomize
            p0[0] += rand(50) - 25
            p0[1] += rand(50) - 25
        end
        x0 = p0[0]; y0 = p0[1]
        x1 = p1[0]; y1 = p1[1]
        x2 = p2[0]; y2 = p2[1]
        mx = (x0 + x1 + x2) / 3.0
        my = (y0 + y1 + y2) / 3.0
        
        tx = mx / 1920.0
        ix = (tx * (g.size - 1)).to_i
        ix = g.size - 2 if ix >= g.size - 1
        ix = 0 if ix < 0
        ix = g.size - 1 if ix >= g.size - 1
        fx = tx * (g.size - 1) - ix
        fx = 0.0 if fx < 0.0
        fx = 1.0 if fx > 1.0
        
        fy = my / 1540.0
#         fy = fy * 0.8 + 0.2
        fy = 0.0 if fy < 0.0
        fy = 1.0 if fy > 1.0
        fy = 3 * fy ** 2 - 2 * fy ** 3
        
        bg_color = ld_mode == 'l' ? [248, 248, 248] : [8, 8, 8]
        # mix RGB
        color = rgb_to_hex(mix(mix(hex_to_rgb(g[ix]), hex_to_rgb(g[ix + 1]), fx), bg_color, fy))
        # mix HSV
#         color = rgb_to_hex(mix(hsv_to_rgb(mix(rgb_to_hsv(hex_to_rgb(g[ix])), rgb_to_hsv(hex_to_rgb(g[ix + 1])), fx)), bg_color, fy))
        if m == 0
#             c1 = 'stroke:none;'
#             c2 = "fill:#000000; filter:url(#blur);"
#             classes[c1] ||= i_to_b62(classes.size)
#             classes[c2] ||= i_to_b62(classes.size)
#             lines << "<circle cx='#{p0[0].to_i}' cy='#{p0[1].to_i}' r='100px' class='c#{classes[c1]} c#{classes[c2]}' />"
        else
            r = r0
            if randomize
                r += rand(20)
            end

            if alpha
                c1 = "stroke:none;"
                c2 = "fill:rgba(#{bg_color.map { |x| x.to_s}.join(',')},0.2);"
                classes[c1] ||= i_to_b62(classes.size)
                classes[c2] ||= i_to_b62(classes.size)
                lines << "<circle cx='#{p0[0].to_i + dx}' cy='#{p0[1].to_i + dy}' r='#{r + dr}' class='c#{classes[c1]} c#{classes[c2]}' />"
            else
                c1 = 'stroke:none;'
                c2 = "fill:#000; fill-opacity:#{sprintf('%1.3f', (1.0 - fy) * (ld_mode == 'l' ? 0.3 : 0.6))}; filter:url(#blur);"
                classes[c1] ||= i_to_b62(classes.size)
                classes[c2] ||= i_to_b62(classes.size)
                lines << "<circle cx='#{p0[0].to_i + dx}' cy='#{p0[1].to_i + dy}' r='#{r + dr}' class='c#{classes[c1]} c#{classes[c2]}' />"

                c1 = 'stroke:none;'
                c2 = "fill:#{color};"
                classes[c1] ||= i_to_b62(classes.size)
                classes[c2] ||= i_to_b62(classes.size)
                lines << "<circle cx='#{p0[0].to_i + dx}' cy='#{p0[1].to_i + dy}' r='#{r + dr}' class='c#{classes[c1]} c#{classes[c2]}' />"
            end
        end
    end
    
    def draw_ngon(n, f, g, p0, p1, p2, m, ld_mode, shadow, classes, lines, &block)
        x0 = p0[0]; y0 = p0[1]
        x1 = p1[0]; y1 = p1[1]
        x2 = p2[0]; y2 = p2[1]
        mx = (x0 + x1 + x2) / 3.0
        my = (y0 + y1 + y2) / 3.0
        
        tx = mx / 1920.0
        ix = (tx * (g.size - 1)).to_i
        ix = g.size - 2 if ix >= g.size - 1
        ix = 0 if ix < 0
        ix = g.size - 1 if ix >= g.size - 1
        fx = tx * (g.size - 1) - ix
        fx = 0.0 if fx < 0.0
        fx = 1.0 if fx > 1.0
        
        fy = my / 1540.0
#         fy = fy * 0.8 + 0.2
        fy = 0.0 if fy < 0.0
        fy = 1.0 if fy > 1.0
        fy = 3 * fy ** 2 - 2 * fy ** 3
        
        bg_color = ld_mode == 'l' ? [248, 248, 248] : [8, 8, 8]
        # mix RGB
        color = rgb_to_hex(mix(mix(hex_to_rgb(g[ix]), hex_to_rgb(g[ix + 1]), fx), bg_color, fy))
        color = yield(color) if block_given?
        # mix HSV
#         color = rgb_to_hex(mix(hsv_to_rgb(mix(rgb_to_hsv(hex_to_rgb(g[ix])), rgb_to_hsv(hex_to_rgb(g[ix + 1])), fx)), bg_color, fy))
        if m == 0
#             c1 = 'stroke:none;'
#             c2 = "fill:#000000; filter:url(#blur);"
#             classes[c1] ||= i_to_b62(classes.size)
#             classes[c2] ||= i_to_b62(classes.size)
#             lines << "<circle cx='#{p0[0].to_i}' cy='#{p0[1].to_i}' r='100px' class='c#{classes[c1]} c#{classes[c2]}' />"
        else
            
            r = 140
            o = 0.7
            if n == 4
                r = 90
                o = 0.5
            elsif n == 6
                r = 80
                o = 0.44
            end
            passes = []
            passes << 0 if shadow == 1
            passes << 1
            passes.each do |pass|
                c1 = 'stroke:none;'
                c2 = pass == 0 ? "fill:#000; fill-opacity:#{sprintf('%1.3f', (1.0 - fy) * (ld_mode == 'l' ? 0.3 : 0.6))}; filter:url(#blur);" : "fill:#{color};"
#                 if pass == 1
#                     c2 = 'stroke: #000000; fill:none;'
#                 end
                a = (tx - 0.5) * 70
    #             a = 0
                classes[c1] ||= i_to_b62(classes.size)
                classes[c2] ||= i_to_b62(classes.size)
                p = []
                (0...n).each do |i|
                    x = p0[0] + r * Math.cos((i + o) * Math::PI * 2.0 / n)
                    y = p0[1] + r * Math.sin((i + o) * Math::PI * 2.0 / n)
                    p << [x, y]
                end
                lines << "<path d='M #{p.map { |_| "#{sprintf('%1.1f', _[0])} #{sprintf('%1.1f', _[1])}"}.join(' ')}' class='c#{classes[c1]} c#{classes[c2]}' transform='translate(#{(p0[0].to_i)}, #{(p0[1].to_i)}) rotate(#{sprintf('%1.1f', a)}) translate(#{-(p0[0].to_i)}, #{-(p0[1].to_i)})' />"
#                 lines << "<rect x='#{p0[0].to_i - r/2}' y='#{p0[1].to_i - r/2}' width='#{r}' height='#{r}px' class='c#{classes[c1]} c#{classes[c2]}' transform='translate(#{(p0[0].to_i)}, #{(p0[1].to_i)}), rotate(#{a}), translate(#{-(p0[0].to_i)}, #{-(p0[1].to_i)})' />"
            end
        end
    end
    
    def get_gradient(color, ld_mode = 'l', spread = 1.0)
        hsv = rgb_to_hsv(hex_to_rgb(color))
        hsv[0] = (hsv[0] + 360 - 60 * spread) % 360
        if ld_mode == 'l'
            hsv[1], hsv[2] = hsv[2], hsv[1]
            hsv[1] = (hsv[1] / 100.0) ** 1.5 * 100.0
        end
        left = rgb_to_hex(hsv_to_rgb(hsv))
        
        hsv = rgb_to_hsv(hex_to_rgb(color))
        hsv[0] = (hsv[0] + 90 * spread) % 360
        if ld_mode == 'l'
            hsv[1], hsv[2] = hsv[2], hsv[1]
            hsv[1] = (hsv[1] / 100.0) ** 1.5 * 100.0
        end
        right = rgb_to_hex(hsv_to_rgb(hsv))

        [left, color, right]
    end

    def darken(c, f = 1.0)
        rgb = hex_to_rgb(c)
        rgb[0] *= f
        rgb[1] *= f
        rgb[2] *= f
        rgb_to_hex(rgb)
    end
    
    def render_bg(out_path, palette)
        style = (palette[19] || '0').to_i
        shadow = style > 1 ? 1 : 0
        ld_mode = palette[0]
        g = ['#' + palette[1, 6], '#' + palette[7, 6], '#' + palette[13, 6]]
        g[1] = rgb_to_hex(mix(hex_to_rgb(g[1]), [255, 255, 255], 0.1))

        height = 1600
        if [8, 9].include?(style)
            height = 2400
        end

        FileUtils.mkpath('/gen/bg')
        STDERR.puts "#{palette} => #{out_path}"
        bg_darken = 0.8
        File.open(out_path, 'w') do |f|
            classes = {}
            lines = []
            bgg = ld_mode == 'l' ? 248 : 8
            bgc = sprintf('#%02x%02x%02x', bgg, bgg, bgg)
            f.puts "<?xml version='1.0' encoding='UTF-8' standalone='no'?>"
            f.puts "<svg xmlns='http://www.w3.org/2000/svg' width='1920' height='#{height}'>"
            f.puts "<defs>"
            f.puts "<linearGradient id='gr1'>"
            f.puts "<stop stop-color='#{g[0]}' offset='0%'/>"
            f.puts "<stop stop-color='#{g[1]}' offset='50%'/>"
            f.puts "<stop stop-color='#{g[2]}' offset='100%'/>"
            f.puts "</linearGradient>"
            f.puts "<linearGradient id='gr2' x1='0' x2='0' y1='0' y2='1'>"
            f.puts "<stop stop-color='#{bgc}' stop-opacity='0' offset='0%'/>"
            f.puts "<stop stop-color='#{bgc}' stop-opacity='1'  offset='100%'/>"
            f.puts "</linearGradient>"
            f.puts "<linearGradient id='gr3'>"
            f.puts "<stop stop-color='#ffffff' stop-opacity='0' offset='0%'/>"
            f.puts "<stop stop-color='#ffffff' stop-opacity='0.15' offset='100%'/>"
            f.puts "</linearGradient>"
            f.puts "<linearGradient id='gr4'>"
            f.puts "<stop stop-color='#000000' stop-opacity='0.1' offset='0%'/>"
            f.puts "<stop stop-color='#000000' stop-opacity='0.0' offset='100%'/>"
            f.puts "</linearGradient>"
            f.puts "</defs>"
            f.puts "<filter id='blur'>"
            f.puts "<feGaussianBlur stdDeviation='5' />"
            f.puts "</filter>"
            f.puts "<rect x='0' y='0' width='1920' height='#{height}' fill='url(#gr1)'/>"
            # f.puts "<rect x='0' y='0' width='1920' height='#{height}' fill='rgba(#{bgg},#{bgg},#{bgg},1)'/>"
            f.puts "<rect x='0' y='0' width='1920' height='#{height}' fill='url(#gr2)'/>"
            if style <= 7
                dx = 115.47
                dy = 100
                dots = []
                y = -300
                shift = 0
                while y < 2000 do
                    line = []
                    x = 1920.0 / 2.0 - dx * 12 + shift * dx * 0.5
                    while x < 2400 do
                        vx = x
                        vy = y
                        phi = rand() * 2.0 * Math::PI
                        r = 0.0
                        if [0].include?(style)
                            r = 30.0
                        end
                        vx = x + r * Math::cos(phi)
                        vy = y + r * Math::sin(phi)
                        line << [vx, vy]
                        x += dx
                    end
                    dots << line
                    y += dy
                    shift = (shift + 1) % 2
                end
                [0, 1].each do |mode|
                    # 2
                    (2...(dots.size - 3)).each do |y|
                        # 2
                        x0 = 0
                        x1 = dots.first.size - 1
                        (2...(dots.first.size - 3)).sort do |a, b|
                            (a - (x1 - x0) / 2.0).abs <=> (b - (x1 - x0) / 2.0).abs
                        end.each do |x|
                            d = y % 2
                            if [0, 1, 2, 3].include?(style)
                                draw_curved_triangle(f, g, 
                                                    dots[y][x], dots[y+1][x+d-1], dots[y+1][x+d], 
                                                    dots[y-1][x+d], 
                                                    dots[y-1][x+d-1], 
                                                    dots[y+1][x+d-2], 
                                                    dots[y+2][x-1], 
                                                    dots[y+2][x+1], 
                                                    dots[y+1][x+d+1], 
                                                    mode, ld_mode, shadow, style == 3, classes, lines)
                                draw_curved_triangle(f, g, 
                                                    dots[y][x], dots[y+1][x+d], dots[y][x+1], 
                                                    dots[y-2][x], #2
                                                    dots[y+1][x+d-1], 
                                                    dots[y+2][x-1], # 1
                                                    dots[y+1][x+d+1], # 2
                                                    dots[y+1][x+d+2], 
                                                    dots[y-1][x+d], # 1
                                                    mode, ld_mode, shadow, style == 3, classes, lines)
                            elsif [4, 5, 6].include?(style)
                                n = 3
                                if style == 5
                                    n = 4
                                elsif style == 6
                                    n = 6
                                end
                                draw_ngon(n, f, g, dots[y][x], dots[y+1][x+d], dots[y][x+1], mode, ld_mode, shadow, classes, lines)
                            elsif style == 7
                                draw_circle(f, g, dots[y][x], dots[y+1][x+d], dots[y][x+1], mode, ld_mode, classes, lines, true, 100, false, 0, 0, 0)
                            end
    #                         break
                        end
    #                         break
                    end
                end
            elsif style == 8
                # (0..50).each do |y|
                #     p = [1920.0/2 + Math.cos(y * 0.2) * 200, 500.0 + Math.sin(y * 0.2) * 200]
                #     r = 1300 - y * 20
                #     lines << "<clipPath id='clip#{y}'>"
                #     lines << "<circle cx='#{p[0].to_i}' cy='#{p[1].to_i}' r='#{r}px' />"
                #     lines << "</clipPath>"
                # end
                # (0..50).each do |y|
                #     p = [1920.0/2 + Math.cos(y * 0.2) * 200, 500.0 + Math.sin(y * 0.2) * 200]
                #     r = 1300 - y * 20
                #     lines << "<g style='clip-path: url(#clip#{y - 1});'>" if y > 0
                #     # lines << "<circle cx='#{p[0].to_i}' cy='#{p[1].to_i}' r='#{r}px' style='fill: rgba(0,0,0,0.05);'/>"
                #     # g2 = g.map { |x| darken(x, 1.0 - y / 51.0)}
                #     draw_circle(f, g, p, p, p, 1, ld_mode, classes, lines, true, r, false)
                # end
                # (0..50).each do |y|
                #     lines << "</g>" if y > 0
                # end
                (0..50).each do |y|
                    p = [y / 50.0 * 2400 - 400, 0.0 + rand(500) - 250]
                    r = 1000
                    # lines << "<g style='clip-path: url(#clip#{y - 1});'>" if y > 0
                    # lines << "<circle cx='#{p[0].to_i}' cy='#{p[1].to_i}' r='#{r}px' style='fill: rgba(0,0,0,0.05);'/>"
                    # g2 = g.map { |x| darken(x, 1.0 - y / 51.0)}
                    draw_circle(f, g, p, p, p, 1, ld_mode, classes, lines, false, r, false, 1800, 1000, 1000)
                end
                lines << "<rect x='0' y='#{height/2}' width='1920' height='#{height/2}' fill='url(#gr2)'/>"
            elsif style == 9
                (-8..8).each do |a|
                    cx = 1920.0 / 2 + a * 120
                    cy = 400.0 + a * 20
                    phi = a * rand(40) + 20.0
                    lines << "<g transform='translate(#{cx},#{cy}) rotate(#{phi})'>"
                    if ld_mode == 'l'
                        lines << "<rect x='-50' y='-#{height}' width='50' height='#{2*height}' fill='url(#gr3)'/>"
                    else
                        lines << "<rect x='0' y='-#{height}' width='50' height='#{2*height}' fill='url(#gr4)'/>"
                    end
                    lines << "</g>"
                end

                lines << "<rect x='0' y='#{height/2}' width='1920' height='#{height/2}' fill='url(#gr2)'/>"
            end
            f.puts "<style>"
            classes.each_pair do |contents, i|
                f.puts ".c#{i} {#{contents}}"
            end
            f.puts "</style>"
            lines.each do |line|
                f.puts line
            end
            f.puts "</svg>"
        end
    end
    
    def render(palette, user = nil)
        rendered_something = false
        (0..9).each do |style|
            ['l', 'd'].each do |ld_mode|
                out_path = "/gen/bg/bg-#{ld_mode}#{palette[0, 3].join('').gsub('#', '')}#{style}.svg"
                next if File.exists?(out_path)
                rendered_something = true
                STDERR.puts "Rendering #{out_path} for #{user || '(no one in particular)'}"
                render_bg(out_path, "#{ld_mode}#{palette[0, 3].join('').gsub('#', '')}#{style}")
            end
        end
        rendered_something
    end
end

if __FILE__ == $0
    STDERR.puts "OY"
    renderer = BackgroundRenderer.new()
    (0..9).each do |style|
        renderer.render_bg("/gen/bg/out-#{style}.svg", "l55beedf9b935e5185d#{style}")
    end
    # (0..9).each do |style|
    #     system("inkscape --export-filename=/gen/bg/out-#{style}.png /gen/bg/out-#{style}.svg")
    # end
end
