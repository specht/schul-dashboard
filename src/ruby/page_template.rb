# Page templates (src/static/*.html): every #{...} in them is Ruby, evaluated
# by the page renderer in main.rb.
#
# - evaluate: one pass from start to end – the search continues after each
#   inserted result, so text that comes out of an expression (data from the
#   database, user input) is never evaluated again, even if it contains #{...}.
# - expand_includes: pages include shared sub-templates with
#   #{File.read('/static/_name.html')} (only files whose name starts with
#   '_'). These are resolved beforehand, as part of the page source, so that
#   their #{...} are evaluated like the page's own.
module PageTemplate
    INCLUDE_PATTERN = /#\{\s*File(?:\.|::)read\(\s*'(\/static\/_[A-Za-z0-9_\-]+\.html)'\s*\)\s*\}/
    MAX_INCLUDE_DEPTH = 5

    def self.expand_includes(source, depth = 0, read: ->(path) { File.read(path, encoding: 'utf-8') })
        source.gsub(INCLUDE_PATTERN) do
            path = Regexp.last_match(1)
            raise "template includes nested too deeply: #{path}" if depth >= MAX_INCLUDE_DEPTH
            expand_includes(read.call(path), depth + 1, read: read)
        end
    end

    # Yields the code of every #{...} (braces inside are counted) and puts the
    # block's result in its place. Returns the new string. Other templates
    # (e.g. mail texts with {...}) pass their opening delimiter.
    #
    # Works on byte positions: character positions in a UTF-8 string with
    # umlauts are counted from the start on every access, which made large
    # pages (the start page, 190 KB) take hundreds of milliseconds. The
    # delimiters and braces are ASCII, so byte positions are safe; the output
    # is built in one new string instead of replacing inside the source.
    OPEN_BRACE = '{'.ord
    CLOSE_BRACE = '}'.ord

    def self.evaluate(source, open: '#{')
        out = String.new(capacity: source.bytesize + 1024, encoding: source.encoding)
        open_size = open.bytesize
        size = source.bytesize
        pos = 0
        while (index = source.byteindex(open, pos))
            out << source.byteslice(pos, index - pos)
            i = index + open_size
            balance = 1
            while i < size && balance > 0
                b = source.getbyte(i)
                balance -= 1 if b == CLOSE_BRACE
                balance += 1 if b == OPEN_BRACE
                i += 1
            end
            code = source.byteslice(index + open_size, i - index - open_size)
            # the closing brace is not part of the code (nor, as before, the
            # last character when the braces never close)
            code = code[0...-1]
            out << (yield code).to_s
            pos = i
        end
        out << source.byteslice(pos, size - pos)
        out
    end
end
