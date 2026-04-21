# frozen_string_literal: true

module Types
  module Quotes
    class VoidReasonEnum < Types::BaseEnum
      graphql_name "QuoteVoidReasonEnum"

      Quote::VOID_REASONS.keys.each do |reason|
        value reason
      end
    end
  end
end
