# frozen_string_literal: true

require "spec_helper"
require "testcontainers"

RSpec.describe Bidi2pdf::Bidi::AddHeadersInterceptor, :chromedriver do
  it "does some thing", skip: "To be defined" do
    Bidi2pdf.configure do |config|
      config.logger.level = Logger::DEBUG
      Chromedriver::Binary.configure { |c| c.logger.level = Logger::INFO }
    end

    session = Bidi2pdf::Bidi::Session.new(session_url: session_url, headless: true)

    session.start

    sleep 10

    expect(session.close).to be_truthy
  end
end
