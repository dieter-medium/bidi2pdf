# frozen_string_literal: true

class DummyClient < Bidi2pdf::Bidi::Client
  attr_reader :response, :cmd_params

  # rubocop: disable  Lint/MissingSuper
  def initialize(response)
    @response = response
    @event_params = []
  end

  # rubocop: enable  Lint/MissingSuper

  def send_cmd(*params) = @cmd_params = params

  def send_cmd_and_wait(*params)
    @cmd_params = params
    yield response
  end

  def on_event(*names)
    @event_params << names
  end

  def event_params(index = 0)
    return @event_params if index.nil?
    return @event_params[index] if index < @event_params.size

    raise ArgumentError, "index out of range for event params"
  end
end
