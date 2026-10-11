# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"

RSpec.describe Bidi2pdf::Notifications::LoggingSubscriberActions do
  let(:io) { StringIO.new }
  let(:subscriber) do
    log = Logger.new(io, level: :info)
    Class.new { include Bidi2pdf::Notifications::LoggingSubscriberActions }.new.tap do |actions|
      actions.define_singleton_method(:logger) { log }
    end
  end

  describe "#network_idle" do
    # The wait raised before it could set the payload's requests (a timeout, for example).
    it "logs an event that carries no requests" do
      event = Struct.new(:payload, :duration).new({}, 12.0)

      subscriber.network_idle(event)

      expect(io.string).to include("0 requests")
    end
  end
end
