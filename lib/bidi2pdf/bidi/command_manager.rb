# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class CommandManager
      class << self
        def initialize_counter
          @id = 0
          @id_mutex = Mutex.new
        end

        def next_id = @id_mutex.synchronize { @id += 1 }
      end

      initialize_counter

      def initialize(socket, logger:)
        @socket = socket
        @logger = logger

        @pending_responses = {}
        @initiated_cmds = {}
      end

      def send_cmd(cmd, store_response: false)
        id = next_id

        if store_response
          init_queue_for id
        else
          @initiated_cmds[id] = true
        end

        payload = cmd.as_payload(id)

        @logger.debug "Sending command: #{redact_sensitive_fields(payload).inspect}"
        @socket.send(payload.to_json)

        id
      end

      def send_cmd_and_wait(cmd, timeout: Bidi2pdf.default_timeout)
        id = send_cmd(cmd, store_response: true)
        response = pop_response id, timeout: timeout

        raise_timeout_error(id, cmd) if response.nil?
        raise CmdError, "Error response: #{response["error"]} #{cmd.inspect}" if response["error"]

        block_given? ? yield(response) : response
      ensure
        @pending_responses.delete(id)
      end

      def pop_response(id, timeout:)
        raise CmdResponseNotStoredError, "No response stored for command ID #{id} or already popped or this command was not send" unless @pending_responses.key?(id)

        @pending_responses[id].pop(timeout: timeout)
      ensure
        @pending_responses.delete(id)
      end

      def handle_response(data)
        if (id = data["id"])
          if @pending_responses.key?(id)
            @pending_responses[id]&.push(data)
            return true
          elsif @initiated_cmds.key?(id)
            @logger.error "Received error: #{data["error"]} for cmd: #{id}" if data["error"]

            return @initiated_cmds.delete(id)
          end
        end

        false
      end

      private

      def init_queue_for(id) = @pending_responses[id] = Thread::Queue.new

      def next_id = self.class.next_id

      def redact_sensitive_fields(obj, sensitive_keys = %w[value token password authorization username])
        case obj
        when Hash
          obj.transform_values.with_index do |v, idx|
            k = obj.keys[idx]
            sensitive_keys.include?(k.to_s.downcase) ? "[REDACTED]" : redact_sensitive_fields(v, sensitive_keys)
          end
        when Array
          obj.map { |item| redact_sensitive_fields(item, sensitive_keys) }
        else
          obj
        end
      end

      def raise_timeout_error(id, cmd)
        @logger.error "Timeout waiting for response to command #{id}, cmd: #{cmd.inspect}"

        raise CmdTimeoutError, "Timeout waiting for response to command ID #{id}"
      end
    end
  end
end
