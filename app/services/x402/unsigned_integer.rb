# frozen_string_literal: true

module X402
  module UnsignedInteger
    DIGITS = /\A\d+\z/

    def self.parse(value)
      case value
      when Integer then value unless value.negative?
      when String then Integer(value, 10) if DIGITS.match?(value)
      end
    end
  end
end
