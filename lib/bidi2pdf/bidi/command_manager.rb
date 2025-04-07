# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class CommandManager
      def initialize(socket, logger:)
        @socket = socket
        @logger = logger

        @id = 0
        @next_id_mutex = Mutex.new
        @pending_responses = {}
      end

      def send_cmd(method, params = {})
        id = next_id
        payload = { id: id, method: method, params: params }

        @logger.debug "Sending command: #{redact_sensitive_fields(payload).inspect}"
        @socket.send(payload.to_json)

        id
      end

      def send_cmd_and_wait(method, params = {}, timeout: Bidi2pdf.default_timeout)
        id = send_cmd(method, params)
        queue = @pending_responses[id]

        response = queue.pop(timeout: timeout)
        raise_timeout_error(id, method, params) if response.nil?
        raise "Error response: #{response["error"]}" if response["error"]

        block_given? ? yield(response) : response
      ensure
        @pending_responses.delete(id)
      end

      def queue_for(id)
        @pending_responses[id]
      end

      def handle_response(data)
        if (id = data["id"]) && @pending_responses.key?(id)
          @pending_responses[id]&.push(data)
        else
          false
        end
      end

      private

      def next_id
        @next_id_mutex.synchronize do
          @id += 1
          @pending_responses[@id] = Thread::Queue.new
          @id
        end
      end

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

      def raise_timeout_error(id, method, params)
        @logger.error "Timeout waiting for response to command #{id}, cmd: #{method}, params: #{redact_sensitive_fields(params).inspect}"
        # rubocop:enable Layout/LineLength
        raise "Timeout waiting for response to command ID #{id}"
      end
    end
  end
end
