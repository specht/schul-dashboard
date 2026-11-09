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
#
# Checksums of files written or read before are remembered together with
# the file's inode, size and modification time. As long as those are
# unchanged, the header is not read again (a stat is much cheaper than
# opening the file) – a file replaced, changed or deleted by someone else is
# still noticed and rewritten.
module GzOutput
    COMMENT_PREFIX = 'sha1:'

    @known = {}
    @known_mutex = Mutex.new

    # Yields an IO to print the content to (like Zlib::GzipWriter.open).
    # Returns true if the file was written, false if it was unchanged.
    def self.write_if_changed(path)
        io = StringIO.new
        yield io
        content = io.string
        sha1 = Digest::SHA1.hexdigest(content)
        return false if current_sha1(path) == sha1

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
        remember(path, sha1)
        true
    end

    # Checksum of the file as it is on disk now: remembered if the file is
    # unchanged since we last saw it, otherwise read from its header.
    def self.current_sha1(path)
        stat = File.stat(path) rescue nil
        return nil unless stat
        signature = [stat.ino, stat.size, stat.mtime]
        known = @known_mutex.synchronize { @known[path] }
        return known[1] if known && known[0] == signature
        sha1 = stored_sha1(path)
        @known_mutex.synchronize { @known[path] = [signature, sha1] } if sha1
        sha1
    end

    def self.remember(path, sha1)
        stat = File.stat(path) rescue nil
        @known_mutex.synchronize do
            if stat
                @known[path] = [[stat.ino, stat.size, stat.mtime], sha1]
            else
                @known.delete(path)
            end
        end
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
