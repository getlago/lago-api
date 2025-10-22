# frozen_string_literal: true

module Validators
  class UniqueCodeInArrayValidator < GraphQL::Schema::Validator
    attr_reader :code_key

    def initialize(code_key: :code, **default_options)
      @code_key = code_key
      super(**default_options)
    end

    def validate(object, context, value)
      duplicates = value.map { it[code_key] }.tally.select { |_, count| count > 1 }.keys

      if duplicates.any?
        "duplicate_currency_code"
      end
    end
  end
end
