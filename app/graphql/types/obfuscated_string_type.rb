# frozen_string_literal: true

module Types
  class ObfuscatedStringType < GraphQL::Schema::Scalar
    PREFIX = "#{"•" * 8}…"

    def self.coerce_result(value, _ctx)
      return nil unless value

      "#{PREFIX}#{value.to_s[-3..]}"
    end

    # NOTE: A form that was filled with the masked value sends it back unchanged on save.
    def self.obfuscated?(value)
      value.to_s.start_with?(PREFIX)
    end
  end
end
