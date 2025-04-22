# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Bidi::CommandManager do
  subject(:command_manager) { described_class.new socket }

  let(:socket) { DummySocket.new }
  let(:cmd) do
    Class.new do
      include Bidi2pdf::Bidi::Commands::Base

      def method_name = "cmd"

      def params = { "a" => "b", "c" => 1 }
    end.new
  end

  before do
    described_class.initialize_counter
  end

  describe "#send_cmd" do
    it "sends a command to the socket" do
      command_manager.send_cmd cmd
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
      result_queue = Thread::Queue.new
      command_manager.send_cmd cmd, result_queue: result_queue
      command_manager.handle_response(data)

      expect(result_queue.pop(0.1)).to eq(data)
    end
  end

  describe "#send_cmd_and_wait" do
    let(:data) { { "id" => 1, "result" => "test" } }

    it "sends a command and waits for a response" do
      waiting_thread = Thread.new do
        sleep 0.1 while socket.args.nil?

        command_manager.handle_response(data)
      end

      response = command_manager.send_cmd_and_wait cmd, timeout: 5

      waiting_thread.join(15)

      expect(response).to eq(data)
    end

    it "raises an error, when the timeout period elapses" do
      expect { command_manager.send_cmd_and_wait cmd, timeout: 0 }.to raise_error(Bidi2pdf::CmdTimeoutError)
    end

    it "raises an error, when the response is an error" do
      error_data = { "id" => 1, "error" => "test" }
      waiting_thread = Thread.new do
        sleep 0.1 while socket.args.nil?

        command_manager.handle_response(error_data)
      end

      expect { command_manager.send_cmd_and_wait cmd, timeout: 1 }.to raise_error(Bidi2pdf::CmdError)

      waiting_thread.join
    end

    it "works with a block" do
      waiting_thread = Thread.new do
        sleep 0.1 while socket.args.nil?

        command_manager.handle_response(data)
      end

      block_result = nil
      command_manager.send_cmd_and_wait cmd, timeout: 5 do |response|
        block_result = response
      end

      waiting_thread.join

      expect(block_result).to eq(data)
    end
  end
end
