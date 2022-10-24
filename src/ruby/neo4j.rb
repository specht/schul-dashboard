require 'socket'

module QtsNeo4j

    class CypherError < StandardError
        def initialize(code, message)
            @code = code
            @message = message
        end

        def to_s
            "Cypher Error\n#{@code}\n#{@message}"
        end
    end

    class BoltBuffer
        def initialize(data)
            @data = data
            @offset = 0
        end

        def next
            v = @data[@offset]
            @offset += 1
            v
        end

        def next_s(length)
            s = @data[@offset, length].pack('C*')
            s.force_encoding('UTF-8')
            @offset += length
            s
        end

        def next_uint8()
            i = @data[@offset]
            @offset += 1
            i
        end

        def next_uint16()
            i = @data[@offset, 2].pack('C*').unpack('S>').first
            @offset += 2
            i
        end

        def next_uint32()
            i = @data[@offset, 4].pack('C*').unpack('L>').first
            @offset += 4
            i
        end

        def next_uint64()
            i = @data[@offset, 8].pack('C*').unpack('Q>').first
            @offset += 8
            i
        end

        def next_int8()
            i = @data[@offset, 1].pack('C*').unpack('c').first
            @offset += 1
            i
        end

        def next_int16()
            i = @data[@offset, 2].pack('C*').unpack('s>').first
            @offset += 2
            i
        end

        def next_int32()
            i = @data[@offset, 4].pack('C*').unpack('l>').first
            @offset += 4
            i
        end

        def next_int64()
            i = @data[@offset, 8].pack('C*').unpack('q>').first
            @offset += 8
            i
        end

        def peek
            @data[@offset]
        end

        def eof?
            @offset >= @data.size
        end

        def rewind
            @offset = 0
        end

        def dump
            offset = 0
            last_offset = 0
            while offset < @data.size
                STDERR.write sprintf("%02x ", @data[offset])
                offset += 1
                if offset % 16 == 0
                    STDERR.write ' ' * 4
                    (last_offset...offset).each do |i|
                        b = @data[i]
                        STDERR.write (b >= 32 && b < 128) ? b.chr : '.'
                    end
                    STDERR.puts
                    last_offset = offset
                end
            end
            (16 - offset + last_offset).times { STDERR.write '   ' }
            STDERR.write ' ' * 4
            (last_offset...offset).each do |i|
                b = @data[i]
                STDERR.write (b >= 32 && b < 128) ? b.chr : '.'
            end
            STDERR.puts
        end
    end

    class BoltSocket

        BOLT_HELLO        = 0x01
        BOLT_GOODBYE      = 0x02
        BOLT_RESET        = 0x0F
        BOLT_RUN          = 0x10
        BOLT_BEGIN        = 0x11
        BOLT_COMMIT       = 0x12
        BOLT_ROLLBACK     = 0x13
        BOLT_DISCARD      = 0x2F
        BOLT_PULL         = 0x3F
        BOLT_NODE         = 0x4E
        BOLT_RELATIONSHIP = 0x52
        BOLT_SUCCESS      = 0x70
        BOLT_RECORD       = 0x71
        BOLT_IGNORED      = 0x7E
        BOLT_FAILURE      = 0x7F

        def initialize
            @socket = nil
            @transaction = 0
            @transaction_failed = false
        end

        def _append(s)
            @buffer += (s.is_a? String) ? s.unpack('C*') : [s]
        end

        def append_uint8(i)
            _append([i].pack('C'))
        end

        def append_uint16(i)
            _append([i].pack('S>'))
        end

        def append_uint32(i)
            _append([i].pack('L>'))
        end

        def append_uint64(i)
            _append([i].pack('Q>'))
        end

        def append_int8(i)
            _append([i].pack('c'))
        end

        def append_int16(i)
            _append([i].pack('s>'))
        end

        def append_int32(i)
            _append([i].pack('l>'))
        end

        def append_int64(i)
            _append([i].pack('q>'))
        end

        def append_s(s)
            s = s.to_s
            if s.bytesize < 16
                append_uint8(0x80 + s.bytesize)
            elsif s.bytesize < 0x100
                append_uint8(0xD0)
                append_uint8(s.bytesize)
            elsif s.bytesize < 0x10000
                append_uint8(0xD1)
                append_uint16(s.bytesize)
            elsif s.bytesize < 0x100000000
                append_uint8(0xD2)
                append_uint32(s.bytesize)
            else
                raise "string cannot exceed 4GB!"
            end
            _append(s)
        end

        def append(v)
            if v.is_a? Array
                append_array(v)
            elsif v.is_a? Hash
                append_dict(v)
            elsif v.is_a? String
                append_s(v)
            elsif v.is_a? NilClass
                append_uint8(0xC0)
            elsif v.is_a? TrueClass
                append_uint8(0xC3)
            elsif v.is_a? FalseClass
                append_uint8(0xC2)
            elsif v.is_a? Integer
                if v >= -16 && v <= -1
                    append_uint8(0x100 + v)
                elsif v >= 0 && v < 0x80
                    append_uint8(v)
                elsif v >= -0x80 && v < 0x80
                    append_uint8(0xC8)
                    append_int8(v)
                elsif v >= -0x8000 && v < 0x8000
                    append_uint8(0xC9)
                    append_int16(v)
                elsif v >= -0x80000000 && v < 0x80000000
                    append_uint8(0xCA)
                    append_int32(v)
                elsif v >= -0x8000000000000000 && v < 0x8000000000000000
                    append_uint8(0xCB)
                    append_int64(v)
                else
                    raise "int is too big"
                end
            else
                raise "Type not supported: #{v.class}"
            end
        end

        def append_dict(d)
            if d.size < 16
                append_uint8(0xA0 + d.size)
            elsif d.size < 0x100
                append_uint8(0xD8)
                append_uint8(d.size)
            elsif d.size < 0x10000
                append_uint8(0xD9)
                append_uint16(d.size)
            elsif d.size < 0x100000000
                append_uint8(0xDA)
                append_uint32(d.size)
            else
                raise "dict cannot exceed 4G entries!"
            end
            d.each_pair do |k, v|
                append_s(k)
                append(v)
            end
        end

        def append_array(a)
            if a.size < 16
                append_uint8(0x90 + a.size)
            elsif a.size < 0x100
                append_uint8(0xD4)
                append_uint8(a.size)
            elsif a.size < 0x10000
                append_uint8(0xD5)
                append_uint16(a.size)
            elsif a.size < 0x100000000
                append_uint8(0xD6)
                append_uint32(a.size)
            else
                raise "list cannot exceed 4G entries!"
            end
            a.each do |v|
                append(v)
            end
        end

        def flush()
            size = @buffer.size
            offset = 0
            while size > 0
                chunk_size = [size, 0xffff].min
                @socket.write([chunk_size].pack('n'))
                @socket.write(@buffer[offset, chunk_size].pack('C*'))
                offset += chunk_size
                size -= chunk_size
            end
            @socket.write([0].pack('n'))
            @buffer = []
        end

        def parse_s(buf)
            f = buf.next
            if f >= 0x80 && f <= 0x8F
                buf.next_s(f & 0xF)
            elsif f == 0xD0
                buf.next_s(buf.next_uint8())
            elsif f == 0xD1
                buf.next_s(buf.next_uint16())
            elsif f == 0xD2
                buf.next_s(buf.next_uint32())
            else
                raise sprintf("unknown string format %02x", f)
            end
        end

        def parse_dict(buf)
            f = buf.next
            count = 0
            if f >= 0xA0 && f <= 0xAF
                count = f & 0xF
            elsif f == 0xD8
                count = buf.next_uint8()
            elsif f == 0xD9
                count = buf.next_uint16()
            elsif f == 0xDA
                count = buf.next_uint32()
            else
                raise sprintf("unknown string dict %02x", f)
            end
            v = {}
            (0...count).map do
                key = parse_s(buf)
                value = parse(buf)
                v[key] = value
            end
            v
        end

        def parse_list(buf)
            f = buf.next
            count = 0
            if f >= 0x90 && f <= 0x9F
                count = f & 0x0F
            elsif f == 0xD4
                count = buf.next_uint8()
            elsif f == 0xD5
                count = buf.next_uint16()
            elsif f == 0xD6
                count = buf.next_uint32()
            else
                raise sprintf("unknown list format %02x", f)
            end
            v = {}
            (0...count).map do
                parse(buf)
            end
        end

        def parse(buf)
            if buf.eof?
                raise 'End of buffer!'
            end
            f = buf.peek
            if f >= 0x80 && f <= 0x8F || f == 0xD0 || f == 0xD1 || f == 0xD2
                parse_s(buf)
            elsif f >= 0x90 && f <= 0x9F || f == 0xD4 || f == 0xD5 || f == 0xD6
                parse_list(buf)
            elsif f >= 0xA0 && f <= 0xAF || f == 0xD8 || f == 0xD9 || f == 0xDA
                parse_dict(buf)
            elsif f >= 0xB0 && f <= 0xBF
                count = buf.next & 0xF
                # STDERR.puts "Parsing #{count} structures!"
                marker = buf.next

                response = {}

                if marker == BOLT_SUCCESS
                    response = {:marker => BOLT_SUCCESS, :data => parse(buf)}
                elsif marker == BOLT_FAILURE
                    response = {:marker => BOLT_FAILURE, :data => parse(buf)}
                elsif marker == BOLT_IGNORED
                    response = {:marker => BOLT_IGNORED}
                elsif marker == BOLT_RECORD
                    response = {:marker => BOLT_RECORD, :data => parse(buf)}
                elsif marker == BOLT_NODE
                    response = {
                        :marker => BOLT_NODE,
                        :id => parse(buf),
                        :labels => parse(buf),
                        :properties => parse(buf),
                    }
                elsif marker == BOLT_RELATIONSHIP
                    response = {
                        :marker => BOLT_RELATIONSHIP,
                        :id => parse(buf),
                        :start_node_id => parse(buf),
                        :end_node_id => parse(buf),
                        :type => parse(buf),
                        :properties => parse(buf),
                    }
                else
                    raise sprintf("Unknown marker: %02x", marker)
                end
                response
            elsif f == 0xC0
                buf.next
                nil
            elsif f == 0xC2
                buf.next
                false
            elsif f == 0xC3
                buf.next
                true
            elsif f == 0xC8
                buf.next
                buf.next_int8()
            elsif f == 0xC9
                buf.next
                buf.next_int16()
            elsif f == 0xCA
                buf.next
                buf.next_int32()
            elsif f == 0xCB
                buf.next
                buf.next_int64()
            elsif f >= 0xF0 && f <= 0xFF
                buf.next
                f - 0x100
            elsif f >= 0 && f <= 0xF7
                buf.next
                f
            else
                raise sprintf("Unknown marker: %02x", f)
            end
        end

        def read_response(&block)
            loop do
                part = []
                loop do
                    length = @socket.read(2).unpack('n').first
                    break if length == 0
                    chunk = @socket.read(length).unpack('C*')
                    part += chunk
                end
                response_dict = parse(BoltBuffer.new(part))
                if response_dict[:marker] == BOLT_FAILURE
                    raise "Bolt error: #{response_dict[:data]['code']}"
                end
                yield response_dict if block_given?
                break if [BOLT_SUCCESS, BOLT_FAILURE, BOLT_IGNORED].include?(response_dict[:marker])
            end
            nil
        end

        def connect()
            # STDERR.write "Connecting to Neo4j via Bolt..."
            @socket = TCPSocket.new('neo4j', 7687)
            # @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
            # @socket.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPIDLE, 50)
            # @socket.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPINTVL, 10)
            # @socket.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPCNT, 5)
            # The line below is important, otherwise we'll have to wait 40ms before every read
            @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
            @buffer = []
            @socket.write("\x60\x60\xB0\x17")
            @socket.write("\x00\x00\x04\x04")
            @socket.write("\x00\x00\x00\x00")
            @socket.write("\x00\x00\x00\x00")
            @socket.write("\x00\x00\x00\x00")
            version = @socket.read(4).unpack('N').first
            if version != 0x00000404
                raise "Unable to establish connection to Neo4j using Bolt protocol version 4.4!"
            end
            data = {
                :routing => nil,
                :scheme => 'none',
                :user_agent => 'qts/0.1'
            }
            append_uint8(0xb1)
            append_uint8(BOLT_HELLO)
            append_dict(data)
            flush()
            read_response() do |data|
                # STDERR.puts " connection established (#{data[:data]['server']})"
            end

            @transaction = 0
            @transaction_failed = false
        end

        def disconnect()
            append_uint8(0xb1)
            append_uint8(BOLT_GOODBYE)
            flush()
        end

        def transaction(&block)
            connect() if @socket.nil?
            if @transaction == 0
                append_uint8(0xb1)
                append_uint8(BOLT_BEGIN)
                append_dict({})
                flush()
                read_response()
                @transaction_failed = false
            end
            @transaction += 1
            begin
                yield
            rescue
                if @transaction == 1
                    # STDERR.puts "Rolling back transaction" if DEBUG
                    append_uint8(0xb1)
                    append_uint8(BOLT_ROLLBACK)
                    flush()
                    read_response()
                    @transaction_failed = true
                end
                raise
            ensure
                @transaction -= 1
            end
            if (@transaction == 0) && (!@transaction_failed)
                append_uint8(0xb1)
                append_uint8(BOLT_COMMIT)
                flush()
                read_response()
                @transaction = 0
                @transaction_failed = false
            end
        end

        def run_query(query, data = {}, &block)
            transaction do
                append_uint8(0xb1)
                append_uint8(BOLT_RUN)
                append_s(query)
                append_dict(data)
                append_dict({}) # options
                flush()
                keys = []
                read_response do |data|
                    keys = (data[:data]['fields'] || {})
                end

                append_uint8(0xb1)
                append_uint8(BOLT_PULL)
                append_dict({:n => -1})
                flush()
                read_response do |data|
                    if data[:marker] == BOLT_RECORD
                        entry = {}
                        keys.each.with_index do |key, i|
                            value = data[:data][i]
                            if value.is_a? Hash
                                if [BOLT_NODE, BOLT_RELATIONSHIP].include?(value[:marker])
                                    value = value[:properties]
                                end
                                value = Hash[value.map { |k, v| [k.to_sym, v] }]
                            elsif value.is_a? Array
                                value.map! do |v2|
                                    if v2.is_a? Hash
                                        if [BOLT_NODE, BOLT_RELATIONSHIP].include?(v2[:marker])
                                            v2 = v2[:properties]
                                        end
                                        v2 = Hash[v2.map { |k, v| [k.to_sym, v] }]
                                    end
                                    v2
                                end
                            end
                            entry[key] = value
                        end
                        yield entry
                    end
                end
            end
        end

        def neo4j_query(query, data = {}, &block)
            rows = []
            run_query(query, data) do |row|
                if block_given?
                    yield row
                else
                    rows << row
                end
            end
            return block_given? ? nil : rows
        end

        def neo4j_query_expect_one(query, data = {})
            rows = neo4j_query(query, data)
            if rows.size != 1
                raise "Expected one result, but got #{rows.size}."
            end
            rows.first
        end
    end

    def transaction(&block)
        @bolt_socket ||= BoltSocket.new()
        @bolt_socket.transaction do
            yield
        end
    end

    def neo4j_query(query, data = {}, &block)
        @bolt_socket ||= BoltSocket.new()
        @bolt_socket.neo4j_query(query, data, &block)
    end

    def neo4j_query_expect_one(query, data = {})
        @bolt_socket ||= BoltSocket.new()
        @bolt_socket.neo4j_query_expect_one(query, data)
    end

    def wait_for_neo4j
        delay = 1
        10.times do
            begin
                neo4j_query("MATCH (n) RETURN n LIMIT 1;")
            rescue
                debug "Waiting #{delay} seconds for Neo4j to come up..."
                sleep delay
                delay += 1
            end
        end
    end

    def cleanup_neo4j
        if @bolt_socket
            @bolt_socket.disconnect()
            @bolt_socket = nil
        end
    end
end
