require_relative 'test_helper'
require 'tmpdir'
require_app 'include/image'

class ImageUploadTest < Minitest::Test
    def setup
        @main = Main.allocate
    end

    def test_accepts_image_extensions
        assert_equal 'jpg', @main.upload_image_extension('Foto.JPG')
        assert_equal 'heic', @main.upload_image_extension('IMG_0001.heic')
        assert_equal 'png', @main.upload_image_extension('a.b.c.png')
    end

    def test_rejects_other_names
        ['x.$(touch pwned)', 'x.`id`', 'x.jpg";id;"', 'x.html', 'x.svg', 'noext', '', nil].each do |name|
            assert_raises(RuntimeError, name.inspect) { @main.upload_image_extension(name) }
        end
    end

    def test_converter_runs_without_shell
        Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
                @main.convert_uploaded_image('in.$(touch pwned)', 'out-$(touch pwned2).jpg', 10)
                refute File.exist?('pwned')
                refute File.exist?('pwned2')
            end
        end
    end
end
