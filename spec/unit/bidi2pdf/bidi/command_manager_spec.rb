# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Bidi::CommandManager do
  subject(:command_manager) { described_class.new socket, logger: logger }

  let(:socket) { DummySocket.new }
  let(:logger) { Logger.new($stdout) }

  describe "#send_cmd" do
    it "sends a command to the socket" do
      command_manager.send_cmd "cmd", { "a" => "b", "c" => 1 }

      actual = JSON.parse(socket.args.first)

      expect(actual).to eq(
                          {
                            "id" => 1,
                            "method" => "cmd",
                            "params" => { "a" => "b", "c" => 1 }
                          }
                        )
    end

    it "stores the response, if the response should be stored" do
      data = { "id" => 1, "result" => "test" }
      command_manager.send_cmd "cmd", { "a" => "b", "c" => 1 }, store_response: true
      command_manager.handle_response(data)

      expect(command_manager.pop_response(1, timeout: 0.1)).to eq(data)
    end
  end

  describe "#pop_response" do
    let(:data) { { "id" => 1, "result" => "test" } }

    before do
      command_manager.send_cmd "cmd", { "a" => "b", "c" => 1 }, store_response: true
    end

    it "returns the response" do
      command_manager.handle_response(data)

      expect(command_manager.pop_response(1, timeout: 0.1)).to eq(data)
    end

    it "returns nil, when a timeout occours" do
      expect(command_manager.pop_response(1, timeout: 0.1)).to be_nil
    end

    it "raises an error, when the response is already poped" do
      command_manager.pop_response 1, timeout: 0.1

      expect { command_manager.pop_response 1, timeout: 0.1 }.to raise_error(Bidi2pdf::CmdResponseNotStoredError)
    end

    it "raises an error, when the response is not stored" do
      id = command_manager.send_cmd "cmd", { "a" => "b", "c" => 1 }, store_response: false

      expect { command_manager.pop_response id, timeout: 0.1 }.to raise_error(Bidi2pdf::CmdResponseNotStoredError)
    end
  end

  describe "#send_cmd_and_wait" do
    let(:data) { { "id" => 1, "result" => "test" } }

    it "sends a command and waits for a response" do
      waiting_thread = Thread.new do
        sleep 0.1 while socket.args.nil?

        command_manager.handle_response(data)
      end

      response = command_manager.send_cmd_and_wait "cmd", { "a" => "b", "c" => 1 }, timeout: 5

      waiting_thread.join

      expect(response).to eq(data)
    end

    it "raises an error, when the timeout period elapses" do
      expect { command_manager.send_cmd_and_wait "cmd", { "a" => "b", "c" => 1 }, timeout: 0 }.to raise_error(Bidi2pdf::CmdTimeoutError)
    end

    it "raises an error, when the response is an error" do
      error_data = { "id" => 1, "error" => "test" }
      waiting_thread = Thread.new do
        sleep 0.1 while socket.args.nil?

        command_manager.handle_response(error_data)
      end

      expect { command_manager.send_cmd_and_wait "cmd", { "a" => "b", "c" => 1 }, timeout: 1 }.to raise_error(Bidi2pdf::CmdError)

      waiting_thread.join
    end

    it "works with a block" do
      waiting_thread = Thread.new do
        sleep 0.1 while socket.args.nil?

        command_manager.handle_response(data)
      end

      block_result = nil
      command_manager.send_cmd_and_wait "cmd", { "a" => "b", "c" => 1 }, timeout: 5 do |response|
        block_result = response
      end

      waiting_thread.join

      expect(block_result).to eq(data)
    end
  end
end
