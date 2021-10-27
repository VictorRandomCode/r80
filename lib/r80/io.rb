# frozen_string_literal: true

module R80
  require_relative 'numbers'

  # Implement I/O ports to support a Z80
  class Io
    def initialize; end

    def in(_port, _value)
      # TODO: very unfinished
      0
    end

    def out(_port, _value)
      # TODO: very unfinished
    end
  end
end
