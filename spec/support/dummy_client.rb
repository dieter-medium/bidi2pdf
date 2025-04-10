# frozen_string_literal: true

class DummyClient < Bidi2pdf::Bidi::Client
  attr_reader :response, :cmd_params, :event_params

  # rubocop: disable  Lint/MissingSuper
  def initialize(response)
    @response = response
  end

  # rubocop: enable  Lint/MissingSuper

  def send_cmd(*params) = @cmd_params = params

  def send_cmd_and_wait(*params)
    @cmd_params = params
    yield response
  end

  def on_event(*names)
    @event_params = names
  end
end
