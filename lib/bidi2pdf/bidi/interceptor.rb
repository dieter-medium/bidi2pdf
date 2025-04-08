# frozen_string_literal: true

module Bidi2pdf
  module Interceptor
    # Network communication phases that can be intercepted
    module Phases
      BEFORE_REQUEST = "beforeRequestSent"
      RESPONSE_STARTED = "responseStarted"
      AUTH_REQUIRED = "authRequired"
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def phases = raise(NotImplementedError)

      def events = raise(NotImplementedError)
    end

    def handle_event(_event) = raise(NotImplementedError)

    def url_patterns = raise(NotImplementedError)

    def context = raise(NotImplementedError)

    def register_with_client(client:)
      @client = client

      client.send_cmd_and_wait("network.addIntercept", {
        context: context,
        phases: self.class.phases,
        urlPatterns: url_patterns
      }) do |response|
        @interceptor_id = response["result"]["intercept"]

        Bidi2pdf.logger.debug "Interceptor added: #{@interceptor_id}"

        client.on_event(*self.class.events, &method(:handle_event))

        self
      end
    end

    def interceptor_id
      @interceptor_id
    end

    def client
      @client
    end
  end
end
