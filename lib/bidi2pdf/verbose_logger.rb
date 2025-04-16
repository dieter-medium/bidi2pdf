# frozen_string_literal: true

module Bidi2pdf
  class VerboseLogger < SimpleDelegator
    VERBOSITY_LEVELS = {
      none: 0,
      low: 1,
      medium: 2,
      high: 3
    }.freeze

    attr_reader :logger, :verbosity

    def initialize(logger, verbosity = :low)
      super(logger)
      self.verbosity = verbosity
      @logger = logger
    end

    def verbosity=(verbosity)
      min_verbosity = VERBOSITY_LEVELS.values.min

      @verbosity = if verbosity.is_a?(Numeric)
                     verbosity = verbosity.to_i
                     max_verbosity = VERBOSITY_LEVELS.values.max

                     verbosity.clamp(min_verbosity, max_verbosity)
                   else
                     VERBOSITY_LEVELS.fetch verbosity.to_sym, min_verbosity
                   end
    end

    def verbosity_sym
      VERBOSITY_LEVELS.find { |_, v| v == verbosity }.first
    end

    def debug1(progname = nil, &)
      return unless debug1?

      logger.debug("[D1] #{progname}", &)
    end

    def debug1?
      verbosity >= 1
    end

    def debug1!
      @verbosity = VERBOSITY_LEVELS[:high]
    end

    def debug2(progname = nil, &)
      return unless debug2?

      logger.debug("[D2] #{progname}", &)
    end

    def debug2?
      verbosity >= 2
    end

    def debug2!
      @verbosity = VERBOSITY_LEVELS[:high]
    end

    def debug3(progname = nil, &)
      return unless debug3?

      logger.debug("[D3] #{progname}", &)
    end

    def debug3?
      verbosity >= 3
    end

    def debug3!
      @verbosity = VERBOSITY_LEVELS[:high]
    end
  end
end
