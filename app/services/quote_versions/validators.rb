# frozen_string_literal: true

module QuoteVersions
  module Validators
    def self.for(result, quote_version:, scope:)
      case quote_version.quote.order_type
      when Quote::ORDER_TYPES[:one_off]
        OneOffValidator.new(result, quote_version:, scope:)
      end
    end
  end
end
