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
        @initiated_cmds = {}
      end

      def send_cmd(method, params = {}, store_response: false)
        id = next_id

        if store_response
          init_queue_for id
        else
          @initiated_cmds[id] = true
        end

        payload = if method.respond_to? :as_payload
                    method.as_payload(id)
                  else
                    { id: id, method: method, params: params }
                  end

        @logger.debug "Sending command: #{redact_sensitive_fields(payload).inspect}"
        @socket.send(payload.to_json)

        id
      end

      def send_cmd_and_wait(method, params = {}, timeout: Bidi2pdf.default_timeout)
        id = send_cmd(method, params, store_response: true)
        response = pop_response id, timeout: timeout

        raise_timeout_error(id, method, params) if response.nil?
        raise CmdError, "Error response: #{response["error"]}" if response["error"]

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
            @logger.error "Received error: #{response["error"]} for cmd: #{id}" if response["error"]

            return @initiated_cmds.delete(id)
          end
        end

        false
      end

      private

      def init_queue_for(id) = @pending_responses[id] = Thread::Queue.new

      def next_id = @next_id_mutex.synchronize { @id += 1 }

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

        raise CmdTimeoutError, "Timeout waiting for response to command ID #{id}"
      end
    end
  end
end
