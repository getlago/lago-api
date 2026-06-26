# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Customers
    class SubscriptionInvoiceIssuingDateAnchorEnum < Types::BaseEnum
      graphql_name "CustomerSubscriptionInvoiceIssuingDateAnchorEnum"
      description "Subscription Invoice Issuing Date Anchor Values"

      ::Customer::SUBSCRIPTION_INVOICE_ISSUING_DATE_ANCHORS.keys.each do |code|
        value code
      end
    end
  end
end
