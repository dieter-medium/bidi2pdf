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
end
