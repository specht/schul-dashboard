require 'fileutils'

# Turns uploaded images into the sizes the pages use (run by the image bot).
# The external programs always get an argument list, never a shell command:
# file names come from uploads.
module ImageConverter
    # <upload_dir>/<tag>.<ext> → <gen_dir>/<tag>-<width>.jpg and .webp, each
    # size made from the next larger one; "p" is a blurred placeholder.
    # Returns the number of files written.
    def self.refresh_uploaded_images(upload_dir, gen_dir, widths)
        file_count = 0
        Dir[File.join(upload_dir, '*')].sort.each do |path|
            # sub folders (e.g. unterstufenparty) are handled where they are used
            next unless File.file?(path)
            tag = File.basename(path).split('.').first
            last_jpg_path = path
            (widths.sort.reverse + [:p]).each do |width|
                jpg_path = File.join(gen_dir, "#{tag}-#{width}.jpg")
                unless File.exist?(jpg_path)
                    STDERR.puts jpg_path
                    size = width == :p ? ['-blur', '0x8'] : ['-resize', "#{width}x>"]
                    system('convert', '-auto-orient', '-set', 'colorspace', 'RGB', last_jpg_path,
                           *size, '-quality', '85', '-sampling-factor', '4:2:0', '-strip', jpg_path)
                    file_count += 1
                end
                webp_path = File.join(gen_dir, "#{tag}-#{width}.webp")
                unless File.exist?(webp_path)
                    STDERR.puts webp_path
                    system('cwebp', '-quiet', jpg_path, '-q', webp_path.include?('-b') ? '100' : '85', '-o', webp_path)
                    file_count += 1
                end
                last_jpg_path = jpg_path
            end
        end
        file_count
    end

    # <bg_dir>/<tag>.svg → <tag>.png, <tag>.jpg and <tag>-512.jpg
    def self.refresh_background_images(bg_dir)
        file_count = 0
        Dir[File.join(bg_dir, '*.svg')].sort.each do |svg_path|
            tag = File.basename(svg_path).split('.').first
            png_path = File.join(bg_dir, "#{tag}.png")
            jpg_path = File.join(bg_dir, "#{tag}.jpg")
            jpg_512_path = File.join(bg_dir, "#{tag}-512.jpg")
            unless File.exist?(png_path)
                STDERR.puts "Creating #{png_path}..."
                system('inkscape', "--export-filename=#{png_path}", svg_path)
                file_count += 1
            end
            unless File.exist?(jpg_path)
                STDERR.puts "Creating #{jpg_path}..."
                system('convert', png_path, jpg_path)
                file_count += 1
            end
            unless File.exist?(jpg_512_path)
                STDERR.puts "Creating #{jpg_512_path}..."
                system('convert', jpg_path, '-resize', '512x', jpg_512_path)
                file_count += 1
            end
        end
        file_count
    end
end
