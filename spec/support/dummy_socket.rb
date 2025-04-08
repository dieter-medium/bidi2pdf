# frozen_string_literal: true

class DummySocket
  attr_reader :args

  def send(*args) = @args = args
end
