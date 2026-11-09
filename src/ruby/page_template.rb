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
    def self.evaluate(source, open: '#{')
        s = source.dup
        pos = 0
        while (index = s.index(open, pos))
            length = open.size
            balance = 1
            while index + length < s.size && balance > 0
                c = s[index + length]
                balance -= 1 if c == '}'
                balance += 1 if c == '{'
                length += 1
            end
            result = (yield s[index + open.size, length - open.size - 1]).to_s
            s[index, length] = result
            pos = index + result.size
        end
        s
    end
end
