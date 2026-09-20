# frozen_string_literal: true

require "monitor"
require "openssl"
require "socket"
require "uri"
require "websocket"

module Bidi2pdf
  module Bidi
    # A threaded WebSocket client on the `websocket` gem's framing - the same shape Selenium's Ruby
    # BiDi client uses. It replaces websocket-client-simple, whose reader pulled one byte at a time
    # (`getc`, then a frame-parse attempt per byte): a printed PDF comes back as one base64 message
    # and every network event for a `data:` navigation echoes the whole URL, so that loop ran
    # millions of times per render - ~730 ms to decode a 700 KB frame, against ~0.5 ms in 16 KB
    # chunks.
    #
    # Emits :open, :message (a WebSocket frame, payload in #data), :error and :close.
    class BufferedWebSocketClient
      READ_CHUNK_BYTES = 16_384

      attr_reader :url

      def self.connect(url, options = {})
        client = new
        yield client if block_given?
        client.connect url, options
        client
      end

      def initialize
        @listeners = Hash.new { |hash, event| hash[event] = [] }
        @listeners_mutex = Mutex.new
        @write_mutex = Mutex.new
        # Re-entrant: a failed write inside #close closes again.
        @close_monitor = Monitor.new
        @handshaked = false
        @closed = false
      end

      def on(event, &listener)
        @listeners_mutex.synchronize { @listeners[event] << listener }
        listener
      end

      def connect(url, options = {})
        return if @socket

        @url = url
        @socket = open_socket(URI.parse(url), options)
        ::WebSocket.should_raise = true
        @handshake = ::WebSocket::Handshake::Client.new url: url, headers: options[:headers]

        socket = @socket # #close clears the ivar; the reader keeps its own reference
        @thread = Thread.new { read_loop(socket, ::WebSocket::Frame::Incoming::Client.new) }
        write @handshake.to_s
      end

      # Commands are sent from whichever thread issues them. On a plain TCP socket one IO#write is
      # already atomic, but OpenSSL::SSL::SSLSocket#write is not, so writes share a lock for wss://.
      def send(data, type: :text)
        return unless open?

        write ::WebSocket::Frame::Outgoing::Client.new(data: data, type: type, version: @handshake.version).to_s
      rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e
        close e
      end

      # Safe from any thread, including the reader's own: the reader sees the peer hang up and
      # closes from inside its loop, so it must neither race a caller closing at the same moment
      # nor be killed before :close has been emitted.
      def close(error = nil)
        @close_monitor.synchronize do
          return if @closed

          say_goodbye unless error
          @closed = true
          @socket&.close
          @socket = nil
          emit :close, error
          @thread.kill if @thread && @thread != Thread.current
        end
      end

      def open? = @handshaked && !@closed

      def closed? = @closed

      private

      def emit(event, *)
        @listeners_mutex.synchronize { @listeners[event].dup }.each { |listener| listener.call(*) }
      end

      def write(bytes)
        @write_mutex.synchronize { @socket&.write bytes }
      end

      def say_goodbye
        write ::WebSocket::Frame::Outgoing::Client.new(data: nil, type: :close, version: @handshake.version).to_s if @handshaked
      rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
        nil # the peer is already gone; there is nobody left to say goodbye to
      end

      def open_socket(uri, options)
        tcp_socket = TCPSocket.new(uri.host, uri.port || (uri.scheme == "wss" ? 443 : 80))
        return tcp_socket unless %w[https wss].include?(uri.scheme)

        ::OpenSSL::SSL::SSLSocket.new(tcp_socket, ssl_context(options)).tap do |ssl_socket|
          ssl_socket.sync_close = true
          ssl_socket.hostname = uri.host
          ssl_socket.connect
        end
      end

      def ssl_context(options)
        ::OpenSSL::SSL::SSLContext.new.tap do |context|
          context.ssl_version = options[:ssl_version] if options[:ssl_version]
          context.verify_mode = options[:verify_mode] if options[:verify_mode]
          context.cert_store = (options[:cert_store] || ::OpenSSL::X509::Store.new).tap(&:set_default_paths)
        end
      end

      def read_loop(socket, frame)
        until @closed
          begin
            consume(socket.readpartial(READ_CHUNK_BYTES), frame)
            # Same terminal-error list as #send/#say_goodbye - Errno::ECONNRESET is already a
            # SystemCallError, so listing it separately was both redundant and, worse, incomplete: any
            # *other* SystemCallError or OpenSSL::SSL::SSLError fell through to the generic rescue
            # below, which only emits :error and loops back into readpartial - on a permanently broken
            # socket (not just ECONNRESET) that re-raises the same error every iteration forever
            # instead of ever closing.
          rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e # EOFError is an IOError
            close e
          rescue StandardError => e
            emit :error, e
          end
        end
      end

      def consume(chunk, frame)
        if @handshaked
          frame << chunk
        else
          @handshake << chunk
          return unless @handshake.finished?

          @handshaked = true
          emit :open
          # Anything the server sent straight after its handshake response is already in this chunk.
          frame << @handshake.leftovers unless @handshake.leftovers.to_s.empty?
        end

        while (message = frame.next)
          dispatch_frame(message)
        end
      end

      # WebSocket control frames (ping/pong/close) must never reach a JSON-parsing consumer -
      # WebSocketDispatcher tries to parse every :message payload as JSON, so a raw close frame
      # would raise JSON::ParserError, and an unanswered ping can make chromedriver or an
      # intermediate proxy tear down an otherwise healthy connection on its own keepalive timeout.
      def dispatch_frame(message)
        case message.type
        when :ping
          send(message.data, type: :pong)
        when :pong
          nil
        when :close
          close
        else
          emit :message, message
        end
      end
    end
  end
end
