# frozen_string_literal: true

require_relative "user_context"

module Bidi2pdf
  module Bidi
    class Browser
      def initialize(client)
        @client = client
      end

      def create_user_context = UserContext.new(@client)
    end
  end
end
