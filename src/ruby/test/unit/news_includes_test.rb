require_relative 'test_helper'
require 'stringio'
require 'kramdown'
# website.rb builds route paths from these when it is loaded
WEBSITE_HOST = 'dashboard.test.invalid' unless defined?(WEBSITE_HOST)
WEBSITE_READ_INFO_SECRET = 'unit-test' unless defined?(WEBSITE_READ_INFO_SECRET)
require_app 'include/website'

# image{…}, gallery{…} and file{…}{…} in news texts (render_news_includes).
# The website (gyst-website) styles this HTML with its own CSS, so the
# classes it knows must stay: image, iw-N, pull-left/right, caption.
class NewsIncludesTest < Minitest::Test
    def setup
        @main = Main.allocate
    end

    def render(s)
        @main.render_news_includes(s)
    end

    def markdown(s)
        Kramdown::Document.new(render(s), :smart_quotes => %w{sbquo lsquo bdquo ldquo}).to_html.strip
    end

    def test_full_width_image_is_marked
        html = render('image{sportfest, "Der Start. Foto: Max Muster"}')
        assert_includes html, "<div class='image image-full'>"
        assert_includes html, "<div class='caption'>Der Start. Foto: Max Muster</div>"
        assert_includes html, "https://#{WEBSITE_HOST}/gen/i/sportfest-1024.webp 1024w"
        refute_includes html, 'pull-'
    end

    def test_full_width_image_without_caption
        html = render('image{sportfest}')
        assert_includes html, "<div class='image image-full'>"
        refute_includes html, 'caption'
    end

    LONG = 'Ein Absatz, der lang genug ist, damit das Bild daneben gut aussieht. ' * 6

    def test_floated_image_keeps_its_classes
        html = render("image{sportfest, l5, \"Foto: Max Muster, Klasse 7b\"}\n#{LONG}")
        assert_includes html, "<div class='image image-float iw-5 pull-left'>"
        assert_includes html, "<div class='caption'>Foto: Max Muster, Klasse 7b</div>"
        html = render("image{sportfest, r4, \"Foto: A\"}\n\n#{LONG}")
        assert_includes html, "<div class='image image-float iw-4 pull-right'>"
    end

    def test_unknown_position_is_part_of_the_caption_as_before
        html = render('image{sportfest, l9, "Foto"}')
        assert_includes html, "<div class='image image-full'>"
    end

    def test_gallery
        html = render('gallery{a, b-2, c_3, "Fotos: Erika Beispiel, Max Muster"}')
        assert_includes html, "<div class='image-gallery gallery-3'>"
        assert_includes html, "<div class='gallery-items'>"
        assert_equal 3, html.scan("<div class='gallery-item'>").size
        %w(a b-2 c_3).each do |slug|
            assert_includes html, "https://#{WEBSITE_HOST}/gen/i/#{slug}-512.jpg 512w"
        end
        # one caption for all photos, after the grid
        assert_equal 1, html.scan("class='caption'").size
        assert_match(/<\/div>\n<div class='caption'>Fotos: Erika Beispiel, Max Muster<\/div>\n<\/div>/, html)
        # three columns: sizes for a third of the width
        assert_includes html, "(min-width: 1200px) #{(1200.0 * 4 / 12 / 12 * 9).to_i}px"
    end

    def test_gallery_without_caption_and_with_two_photos
        html = render('gallery{a, b}')
        assert_includes html, "<div class='image-gallery gallery-2'>"
        refute_includes html, 'caption'
        assert_includes html, "(min-width: 1200px) #{(1200.0 * 6 / 12 / 12 * 9).to_i}px"
    end

    def test_gallery_with_bad_names_stays_text
        ['gallery{a b, c}', "gallery{a'x, b}", 'gallery{ , }', "gallery{#{(1..13).map { |i| "b#{i}" }.join(', ')}}"].each do |s|
            assert_equal s, render(s), s
        end
    end

    def test_gallery_and_image_in_one_text
        html = render("Text.\n\nimage{x, \"Foto: A\"}\n\ngallery{y, z, \"Fotos: B\"}")
        assert_includes html, "<div class='image image-full'>"
        assert_includes html, "<div class='image-gallery gallery-2'>"
        refute_includes html, 'gallery{'
        refute_includes html, 'image{'
    end

    def test_markdown_keeps_blocks_apart
        html = markdown("Einstieg.\n\nimage{x, l5, \"Foto: A\"}\nText daneben.\n\ngallery{y, z, \"Fotos: B\"}")
        assert_includes html, '<p>Einstieg.</p>'
        assert_includes html, '<div class="image image-float iw-5 pull-left">'
        assert_includes html, '<p>Text daneben.</p>'
        assert_includes html, '<div class="image-gallery gallery-2">'
    end

    # the website's article page: beitrag-<timestamp in base 36>
    def test_public_url
        assert_equal 'https://www.beispielschule.de/beitrag-t5n7ib', Main.news_public_url(1_763_000_003, 'https://www.beispielschule.de')
        # the website's example
        assert_equal 'https://www.beispielschule.de/beitrag-snre93', Main.news_public_url(1_732_962_279, 'https://www.beispielschule.de/')
        assert_nil Main.news_public_url(1_763_000_003, nil)
        # without the setting (or before the website has the pages): no links
        assert_nil Main.news_public_url_base unless defined?(SCHOOL_WEBSITE_URL) && defined?(WEBSITE_ARTICLE_LINKS) && WEBSITE_ARTICLE_LINKS
    end

    # pos=x,y (percent) before the caption: the part that stays visible
    # when the image is cropped
    def test_parse_image
        assert_equal ['a', nil, 'Foto: A, B', nil], @main.parse_news_image('a, "Foto: A, B"')
        assert_equal ['a', 'r5', 'Foto: A', nil], @main.parse_news_image('a, r5, "Foto: A"')
        assert_equal ['a', 'r5', 'Foto: A', [30, 60]], @main.parse_news_image('a, r5, pos=30,60, "Foto: A"')
        assert_equal ['a', nil, 'Foto: A', [0, 100]], @main.parse_news_image('a,pos=0,100,"Foto: A"')
        assert_equal ['a', nil, '', [30, 60]], @main.parse_news_image('a, pos=30,60')
        assert_equal ['a', 'l4', '', [100, 7]], @main.parse_news_image('a, l4, pos=250,7')
        # only before the caption: in the caption it is text
        assert_equal ['a', nil, 'Bild pos=1,2', nil], @main.parse_news_image('a, "Bild pos=1,2"')
        assert_equal ['a', nil, '', nil], @main.parse_news_image('a')
    end

    def test_image_with_position
        html = render('image{a, pos=30,60, "Foto: A"}')
        assert_includes html, "<div class='image image-full' data-pos='30 60'>"
        assert_includes html, "style='object-position: 30% 60%'"
        assert_includes html, "<div class='caption'>Foto: A</div>"
        html = render('image{a, r5, pos=10,90, "Foto: A"}')
        assert_includes html, "<div class='image image-float iw-5 pull-right' data-pos='10 90'>"
        assert_includes html, "style='object-position: 10% 90%'"
        # without a position: as before
        html = render('image{a, "Foto: A"}')
        refute_includes html, 'data-pos'
        assert_includes html, "style='object-position: 50% 50%'"
    end

    def test_image_row
        html = render('images{3:2, "Fotos: Erika Beispiel"}{image{a, pos=20,30, "Der Start"} image{b, r5, "Das Ziel"}}')
        assert_includes html, "<div class='image-row ratio-3-2 images-2'>"
        assert_includes html, "<div class='image image-in-row' data-pos='20 30'>"
        assert_includes html, "style='object-position: 20% 30%'"
        # l3–r6 don't apply in a row; the default position is the middle
        assert_includes html, "<div class='image image-in-row' data-pos='50 50'>"
        refute_includes html, 'pull-right'
        assert_includes html, "<div class='caption'>Der Start</div>"
        assert_includes html, "<div class='caption'>Das Ziel</div>"
        assert_match(/<\/div>\n<div class='caption image-row-caption'>Fotos: Erika Beispiel<\/div>\n<\/div>\n\z/, html)
        refute_includes html, 'image{'
        # two columns: sizes for half the width
        assert_includes html, "(min-width: 1200px) #{(1200.0 * 6 / 12 / 12 * 9).to_i}px"

        html = render("images{16:9}{\nimage{a} image{b}\nimage{c, \"Foto: C\"}\n}")
        assert_includes html, "<div class='image-row ratio-16-9 images-3'>"
        assert_equal 3, html.scan("<div class='image image-in-row'").size
        refute_includes html, 'image-row-caption'
        %w(4:3 1:1).each { |r| assert_includes render("images{#{r}}{image{a} image{b}}"), "ratio-#{r.tr(':', '-')} images-2" }
    end

    # anything else stays a row of text around the single images
    def test_image_row_needs_a_known_ratio_and_two_or_three_images
        ['images{5:4}{image{a} image{b}}', 'images{3:2}{image{a}}', 'images{3:2}{image{a} image{b} image{c} image{d}}',
         "images{3:2}{image{a'x} image{b}}", 'images{3:2}{image{a} text image{b}}'].each do |s|
            html = render(s)
            refute_includes html, 'image-row', s
            assert_includes html, 'images{', s
        end
    end

    def test_markdown_keeps_a_row_one_block
        html = markdown("Einstieg.\n\nimages{3:2}{image{a, \"A\"} image{b, \"B\"}}\n\nWeiter.")
        assert_includes html, '<p>Einstieg.</p>'
        assert_includes html, '<div class="image-row ratio-3-2 images-2">'
        assert_includes html, '<p>Weiter.</p>'
        refute_match(/<p>\s*<div/, html)
    end

    def test_file
        html = render('file{elternbrief.pdf}{Der Elternbrief}')
        assert_includes html, "<i class='file-type fa fa-file-pdf-o'></i>"
        assert_includes html, "<a href='https://#{WEBSITE_HOST}/f/elternbrief.pdf' target='_blank'>Der Elternbrief</a>"
    end
end
