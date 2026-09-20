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
end
