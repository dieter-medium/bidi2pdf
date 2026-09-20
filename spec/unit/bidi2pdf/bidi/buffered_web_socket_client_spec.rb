# frozen_string_literal: true

require "spec_helper"
require "socket"
require "websocket"

RSpec.describe Bidi2pdf::Bidi::BufferedWebSocketClient do
  # A real WebSocket server on a loopback port - the read loop is the whole point of this class, so
  # it talks to a real socket rather than a double.
  def with_server(frames:, with_handshake: false)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new { serve(server.accept, frames, with_handshake) }

    yield "ws://127.0.0.1:#{server.addr[1]}/"
  ensure
    thread&.join(2)
    server&.close
  end

  def serve(connection, frames, with_handshake)
    handshake = WebSocket::Handshake::Server.new
    handshake << connection.readpartial(4096) until handshake.finished?
    payload = frames.map { |data| WebSocket::Frame::Outgoing::Server.new(data: data, type: :text, version: handshake.version).to_s }.join

    # One write or two decides whether the first frame shares a packet with the handshake response.
    (with_handshake ? [handshake.to_s + payload] : [handshake.to_s, payload]).each { |bytes| connection.write bytes }
  ensure
    connection.close
  end

  def receive(url, expected:)
    messages = Thread::Queue.new
    closed = Thread::Queue.new
    client = described_class.connect(url) do |socket|
      socket.on(:message) { |message| messages << message.data }
      socket.on(:close) { closed << true }
    end

    [Array.new(expected) { messages.pop(timeout: 5) }, closed.pop(timeout: 5)]
  ensure
    client&.close
  end

  # Accepts one client, completes the handshake, then collects every text frame the client sends
  # until it hangs up.
  def with_recording_server
    server = TCPServer.new("127.0.0.1", 0)
    received = Thread::Queue.new
    thread = Thread.new { record(server.accept, received) }

    yield "ws://127.0.0.1:#{server.addr[1]}/", received
  ensure
    thread&.join(2)
    server&.close
  end

  def record(connection, received)
    frame = WebSocket::Frame::Incoming::Server.new(version: accept_handshake(connection).version)
    loop do
      frame << connection.readpartial(65_536)
      while (message = frame.next)
        received << message.data if message.type == :text
      end
    end
  rescue IOError, SystemCallError
    nil
  ensure
    connection.close
  end

  # Completes the handshake, sends one frame of the given type/data to the client, then records
  # every frame (type + data) the client sends back until it hangs up - for asserting how the
  # client responds to a control frame (ping/close), as opposed to with_recording_server above,
  # which only ever records :text frames and is used by the plain data-transfer specs.
  def with_server_frame(type:, data: nil)
    server = TCPServer.new("127.0.0.1", 0)
    received = Thread::Queue.new
    thread = Thread.new { serve_frame_and_record(server, type, data, received) }

    yield "ws://127.0.0.1:#{server.addr[1]}/", received
  ensure
    thread&.join(2)
    server&.close
  end

  def serve_frame_and_record(server, type, data, received)
    connection = server.accept
    handshake = accept_handshake(connection)
    connection.write WebSocket::Frame::Outgoing::Server.new(data: data, type: type, version: handshake.version).to_s

    frame = WebSocket::Frame::Incoming::Server.new(version: handshake.version)
    loop do
      frame << connection.readpartial(65_536)
      while (message = frame.next)
        received << message
      end
    end
  rescue IOError, SystemCallError
    nil
  ensure
    connection.close
  end

  def accept_handshake(connection)
    WebSocket::Handshake::Server.new.tap do |handshake|
      handshake << connection.readpartial(4096) until handshake.finished?
      connection.write handshake.to_s
    end
  end

  def connect_and_wait(url)
    opened = Thread::Queue.new
    client = described_class.connect(url) { |socket| socket.on(:open) { opened << true } }
    opened.pop(timeout: 5)
    client
  end

  it "delivers a message far larger than one read chunk intact" do
    big = "x" * (described_class::READ_CHUNK_BYTES * 40)

    with_server(frames: [big]) do |url|
      messages, = receive(url, expected: 1)

      expect(messages).to eq([big])
    end
  end

  it "delivers every message when several arrive in one read" do
    with_server(frames: %w[first second third]) do |url|
      messages, = receive(url, expected: 3)

      expect(messages).to eq(%w[first second third])
    end
  end

  it "delivers a message sent in the same packet as the handshake response" do
    with_server(frames: ["early"], with_handshake: true) do |url|
      messages, = receive(url, expected: 1)

      expect(messages).to eq(["early"])
    end
  end

  it "emits close when the server hangs up" do
    with_server(frames: ["bye"]) do |url|
      _, closed = receive(url, expected: 1)

      expect(closed).to be(true)
    end
  end

  it "keeps frames intact when several threads send at once" do
    payloads = Array.new(8) { |index| index.to_s * 200_000 }

    with_recording_server do |url, received|
      client = connect_and_wait(url)
      payloads.map { |payload| Thread.new { client.send(payload) } }.each(&:join)
      messages = Array.new(payloads.size) { received.pop(timeout: 5) }
      client.close

      expect(messages).to match_array(payloads)
    end
  end

  it "does not raise when sending after the server hung up" do
    with_server(frames: ["bye"]) do |url|
      client = described_class.connect(url)
      sleep 0.05 until client.closed?

      expect { client.send("too late") }.not_to raise_error
    end
  end

  it "replies to a real ping frame with a pong of the same payload" do
    with_server_frame(type: :ping, data: "keepalive") do |url, received|
      client = described_class.connect(url)

      expect(received.pop(timeout: 5)).to have_attributes(type: :pong, data: "keepalive")

      client.close
    end
  end

  it "does not emit :message for a ping frame" do
    with_server_frame(type: :ping, data: "keepalive") do |url, received|
      messages = Thread::Queue.new
      client = described_class.connect(url) { |socket| socket.on(:message) { |m| messages << m } }
      received.pop(timeout: 5) # synchronization: the pong reply proves dispatch_frame already ran

      expect(messages).to be_empty

      client.close
    end
  end

  it "sends a close frame back for a real close frame from the peer (not just a dropped TCP connection)" do
    with_server_frame(type: :close) do |url, received|
      described_class.connect(url)

      expect(received.pop(timeout: 5).type).to eq(:close)
    end
  end

  it "emits :close for a real close frame from the peer" do
    with_server_frame(type: :close) do |url, received|
      closed = Thread::Queue.new
      described_class.connect(url) { |socket| socket.on(:close) { |error| closed << error } }
      received.pop(timeout: 5) # synchronization: proves the close was already dispatched

      expect(closed.pop(timeout: 5)).to be_nil
    end
  end

  it "does not emit :message for a real close frame from the peer" do
    with_server_frame(type: :close) do |url, received|
      messages = Thread::Queue.new
      described_class.connect(url) { |socket| socket.on(:message) { |m| messages << m } }
      received.pop(timeout: 5) # synchronization

      expect(messages).to be_empty
    end
  end

  # SystemCallError/OpenSSL::SSL::SSLError previously fell through read_loop's generic
  # `rescue StandardError` (only Errno::ECONNRESET was treated as terminal), which would loop
  # forever re-raising the same error on a permanently broken socket instead of ever closing -
  # a real socket can't reliably be made to raise these on demand, so a minimal double stands in
  # for the socket here, isolating exactly the exception-routing behavior under test.
  [Errno::ETIMEDOUT, OpenSSL::SSL::SSLError].each do |error_class|
    it "closes rather than looping forever on a #{error_class} from the read loop" do
      client = described_class.new
      received_error = nil
      client.on(:close) { |error| received_error = error }

      socket = Object.new
      socket.define_singleton_method(:readpartial) { |_bytes| raise error_class }
      frame = Object.new

      # __send__, not send: this class defines its own public #send (for WebSocket sends), which
      # shadows Kernel#send - plain .send(:read_loop, ...) would call *that* #send instead of
      # dispatching to the private read_loop.
      client.__send__(:read_loop, socket, frame)

      expect(received_error).to be_a(error_class)
    end
  end
end
