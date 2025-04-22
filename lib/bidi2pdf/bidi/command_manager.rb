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

        @pending_responses = {}
        @initiated_cmds = {}
      end

      def send_cmd(cmd, store_response: false)
        id = next_id

        Bidi2pdf.notification_service.instrument("send_cmd.bidi2pdf", id: id, cmd: cmd) do |instrumentation_payload|
          if store_response
            init_queue_for id
          else
            @initiated_cmds[id] = true
          end

          payload = cmd.as_payload(id)

          instrumentation_payload[:cmd_payload] = payload

          @socket.send(payload.to_json)
        end

        id
      end

      def send_cmd_and_wait(cmd, timeout: Bidi2pdf.default_timeout, &block)
        Bidi2pdf.notification_service.instrument("send_cmd_and_wait.bidi2pdf", cmd: cmd, timeout: timeout) do |instrumentation_payload|
          id = send_cmd(cmd, store_response: true)

          instrumentation_payload[:id] = id

          response = pop_response id, timeout: timeout

          instrumentation_payload[:response] = response

          raise CmdTimeoutError, "Timeout waiting for response to command ID #{id}" if response.nil?

          raise Bidi2pdf::CmdError.new(cmd, response) if response["error"]

          block ? block.call(response) : response
        ensure
          @pending_responses.delete(id)
        end
      end

      def pop_response(id, timeout:)
        raise CmdResponseNotStoredError, "No response stored for command ID #{id} or already popped or this command was not send" unless @pending_responses.key?(id)

        @pending_responses[id].pop(timeout: timeout)
      ensure
        @pending_responses.delete(id)
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
            elsif @initiated_cmds.key?(id)
              @initiated_cmds.delete(id)

              return true
            end
          end

          instrumentation_payload[:handled] = false

          false
        end
      end

      private

      def init_queue_for(id) = @pending_responses[id] = Thread::Queue.new

      def next_id = self.class.next_id
    end
  end
end
