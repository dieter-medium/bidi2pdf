# frozen_string_literal: true

require_relative "bidi2pdf/utils"
require_relative "bidi2pdf/launcher"
require_relative "bidi2pdf/bidi/session"

require "logger"

module Bidi2pdf
  class Error < StandardError; end

  @logger = Logger.new($stdout)
  @logger.level = Logger::DEBUG

  @default_timeout = 60

  class << self
    attr_accessor :logger, :default_timeout

    # Allow configuration through a block
    def configure
      yield self if block_given?
    end
  end
end
