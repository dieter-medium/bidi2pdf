# frozen_string_literal: true

require "monitor"
require "websocket-client-simple"

module Bidi2pdf
  module Bidi
    # websocket-client-simple reads its socket one byte at a time (`getc`, then a frame-parse attempt
    # per byte). A printed PDF comes back as one base64 message, and every network event for a
    # `data:` navigation echoes the whole URL, so that loop ran millions of times per render -
    # measured at ~730 ms to decode a 700 KB frame, against ~0.5 ms when fed in 16 KB chunks.
    # Only the read loop differs from the parent; events, #send and #close are inherited.
    class BufferedWebSocketClient < ::WebSocket::Client::Simple::Client
      READ_CHUNK_BYTES = 16_384

      def self.connect(url, options = {})
        client = new
        yield client if block_given?
        client.connect url, options
        client
      end

      def initialize
        super
        @close_monitor = Monitor.new
      end

      def connect(url, options = {})
        return if @socket

        @url = url
        @socket = open_socket(URI.parse(url), options)
        ::WebSocket.should_raise = true
        @handshake = ::WebSocket::Handshake::Client.new url: url, headers: options[:headers]
        @handshaked = false
        @pipe_broken = false
        @closed = false

        once :__close do |err|
          close
          emit :close, err
        end

        @thread = Thread.new { read_loop(::WebSocket::Frame::Incoming::Client.new) }
        @socket.write @handshake.to_s
      end

      # Replaces the parent's #close, which could rely on its reader never noticing the peer hang
      # up. This reader does, so two things differ. It is serialised: the reader (on EOF) and the
      # caller may close concurrently, one closing the socket while the other still writes the close
      # frame - re-entrant, because :__close's handler calls #close again. And it never kills the
      # thread it is running on: the parent's unconditional Thread.kill would stop the reader before
      # it could emit :close.
      def close
        @close_monitor.synchronize do
          return if @closed

          send_close_frame
          @closed = true
          @socket&.close
          @socket = nil
          emit :__close
          Thread.kill @thread if @thread && @thread != Thread.current
        end
      end

      private

      def send_close_frame
        send nil, type: :close unless @pipe_broken
      rescue IOError, SystemCallError
        @pipe_broken = true
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

      def read_loop(frame)
        until @closed
          begin
            consume(@socket.readpartial(READ_CHUNK_BYTES), frame)
          rescue IOError, Errno::ECONNRESET => e # EOFError is an IOError
            emit :__close, e unless @closed
            break
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
          emit :message, message
        end
      end
    end
  end
end
