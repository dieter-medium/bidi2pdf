# frozen_string_literal: true

module Bidi2pdf
  class LoggingSubscriber
    attr_reader :logger

    def initialize(logger: Logger.new($stdout))
      @logger = logger
      Bidi2pdf::Notifications.subscribe("handle_response.bidi2pdf", &method(:handle_response))
      Bidi2pdf::Notifications.subscribe("send_cmd.bidi2pdf", &method(:send_cmd))
      Bidi2pdf::Notifications.subscribe("send_cmd_and_wait.bidi2pdf", &method(:send_cmd_and_wait))
    end

    def handle_response(event)
      payload = event.payload

      if payload[:error]
        logger.error "Received error: #{payload[:error].inspect} for cmd: #{payload[:id] || "-"}"
      elsif !payload[:handled]
        Bidi2pdf.logger.warn "Unknown response: #{payload[:data].inspect}"
      end
    end

    def send_cmd(event)
      logger.debug do
        payload = redact_sensitive_fields(event.payload[:cmd_payload])
        "Sending command: #{payload.inspect} (#{event.duration.round(1)}ms)"
      end
    end

    def send_cmd_and_wait(event)
      return unless event.payload[:exception]

      payload = redact_sensitive_fields(event.payload[:cmd]&.params || {})
      logger.error "Error sending command: #{payload} (#{event.duration.round(1)}ms) - #{event.payload[:exception].inspect}"
    end

    private

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
  end

  LoggingSubscriber.new
end
