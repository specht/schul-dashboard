require_relative 'test_helper'
require 'tmpdir'
require 'base64'
require_app 'include/image_converter'

# The image bot converts every uploaded image into several sizes. File names
# come from uploads, so the converters must run without a shell.
class ImageConverterTest < Minitest::Test
    PNG = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=')

    def test_uploaded_images_without_shell_and_without_sub_folders
        Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
                uploads = File.join(dir, 'uploads')
                gen = File.join(dir, 'gen')
                FileUtils.mkpath([uploads, gen])
                File.binwrite(File.join(uploads, 'foto.png'), PNG)
                File.binwrite(File.join(uploads, 'x$(touch pwned).png'), PNG)
                File.binwrite(File.join(uploads, 'y`touch pwned2`.png'), PNG)
                # images of the Unterstufenparty live in a folder of their own
                FileUtils.mkpath(File.join(uploads, 'unterstufenparty'))

                ImageConverter.refresh_uploaded_images(uploads, gen, [16, 32])

                refute File.exist?('pwned')
                refute File.exist?('pwned2')
                assert File.exist?(File.join(gen, 'foto-32.jpg'))
                assert File.exist?(File.join(gen, 'foto-16.jpg'))
                assert File.exist?(File.join(gen, 'foto-p.jpg'))
                assert_empty Dir[File.join(gen, 'unterstufenparty-*')]
            end
        end
    end
end
