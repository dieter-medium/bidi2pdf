# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class CommandManager
      class << self
        def initialize_counter
          @id = Concurrent::AtomicFixnum.new(0)
        end

        def next_id = @id.increment
      end

      initialize_counter

      def initialize(socket)
        @socket = socket

        @pending_responses = Concurrent::Hash.new
      end

      def send_cmd(cmd, result_queue: nil)
        id = next_id

        Bidi2pdf.notification_service.instrument("send_cmd.bidi2pdf", id: id, cmd: cmd) do |instrumentation_payload|
          init_queue_for id, result_queue

          payload = cmd.as_payload(id)

          instrumentation_payload[:cmd_payload] = payload

          @socket.send(payload.to_json)
        end

        id
      end

      def send_cmd_and_wait(cmd, timeout: Bidi2pdf.default_timeout, &block)
        result_queue = Thread::Queue.new

        Bidi2pdf.notification_service.instrument("send_cmd_and_wait.bidi2pdf", cmd: cmd, timeout: timeout) do |instrumentation_payload|
          id = send_cmd(cmd, result_queue: result_queue)

          instrumentation_payload[:id] = id

          response = result_queue.pop(timeout: timeout)

          instrumentation_payload[:response] = response

          raise CmdTimeoutError, "Timeout waiting for response to command ID #{id}" if response.nil?

          raise Bidi2pdf::CmdError.new(cmd, response) if response["error"]

          block ? block.call(response) : response
        ensure
          @pending_responses.delete(id)
        end
      end

      def handle_response(data)
        Bidi2pdf.notification_service.instrument("handle_response.bidi2pdf", data: data) do |instrumentation_payload|
          instrumentation_payload[:error] = data["error"] if data["error"]

          if (id = data["id"])
            instrumentation_payload[:handled] = true
            instrumentation_payload[:id] = id

            if @pending_responses.key?(id)
              @pending_responses[id]&.push(data)

              return true
            end
          end

          instrumentation_payload[:handled] = false

          false
        ensure
          @pending_responses.delete id
        end
      end

      private

      def init_queue_for(id, result_queue) = @pending_responses[id] = result_queue

      def next_id = self.class.next_id
    end
  end
end
