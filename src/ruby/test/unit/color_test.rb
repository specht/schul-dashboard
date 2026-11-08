require_relative 'test_helper'
require_app 'include/color'

class ColorTest < Minitest::Test
    def setup
        @main = Main.allocate
    end

    def test_hex_to_rgb
        assert_equal [255, 128, 0], @main.hex_to_rgb('#ff8000')
        assert_equal [255, 128, 0], @main.hex_to_rgb('#FF8000')
    end

    def test_luminance
        assert_in_delta 255.0, @main.luminance('#ffffff'), 0.01
        assert_in_delta 0.0, @main.luminance('#000000'), 0.01
    end

    def test_palette_from_color_scheme
        # 'l' = light background, then left / primary / right color, then style
        palette = @main.color_palette_for_color_scheme('l788aa3e8a598b565760')
        assert_equal '#788aa3', palette[:left]
        assert_equal '#e8a598', palette[:primary]
        assert_equal '#b56576', palette[:right]
        assert palette[:is_light], 'a light primary color should count as light'

        dark_primary = @main.color_palette_for_color_scheme('d0000000000330000000')
        refute dark_primary[:is_light]
    end
end
