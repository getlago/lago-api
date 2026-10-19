# frozen_string_literal: true

module Types
  module Invoices
    class ProgressiveBillingTriggerEnum < Types::BaseEnum
      graphql_name "InvoiceProgressiveBillingTriggerEnum"

      Invoice::PROGRESSIVE_BILLING_TRIGGERS.keys.each do |trigger|
        value trigger
      end
    end
  end
end
