require 'digest'
require 'stringio'
require 'zlib'

# Writes generated gzip files (timetables, messages, homework …) only when
# their content changed, and always atomically.
#
# The SHA1 of the uncompressed content is stored in the gzip header comment
# of each file. Before writing, the header of the existing file is read
# (cheap, nothing is decompressed); if it carries the same checksum, the file
# is left alone. Because the checksum lives in the file itself, it can never
# disagree with what is on disk – after a crash or restart the next update
# simply compares again. Everything is still computed every time, so this is
# exactly as safe as rewriting all files, just much faster.
#
# New files are written to a temporary file and renamed, so readers (nginx,
# other services) never see a half-written file.
module GzOutput
    COMMENT_PREFIX = 'sha1:'

    # Yields an IO to print the content to (like Zlib::GzipWriter.open).
    # Returns true if the file was written, false if it was unchanged.
    def self.write_if_changed(path)
        io = StringIO.new
        yield io
        content = io.string
        sha1 = Digest::SHA1.hexdigest(content)
        return false if stored_sha1(path) == sha1

        temp = "#{path}.tmp-#{Process.pid}-#{Thread.current.object_id}"
        begin
            Zlib::GzipWriter.open(temp) do |gz|
                gz.comment = "#{COMMENT_PREFIX}#{sha1}"
                gz.write(content)
            end
            File.rename(temp, path)
        ensure
            File.unlink(temp) if File.exist?(temp)
        end
        true
    end

    # The checksum stored in an existing file's header, or nil.
    def self.stored_sha1(path)
        return nil unless File.exist?(path)
        comment = Zlib::GzipReader.open(path) { |gz| gz.comment }
        comment&.start_with?(COMMENT_PREFIX) ? comment.sub(COMMENT_PREFIX, '') : nil
    rescue Zlib::Error, IOError, SystemCallError
        nil
    end
end
