# frozen_string_literal: true

module Types
  module Quotes
    class BackdatedBillingEnum < Types::BaseEnum
      graphql_name "QuoteBackdatedBillingEnum"

      Quote::BACKDATED_BILLING_OPTIONS.keys.each do |option|
        value option
      end
    end
  end
end
