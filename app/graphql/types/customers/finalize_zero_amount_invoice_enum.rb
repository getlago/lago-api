# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Customers
    class FinalizeZeroAmountInvoiceEnum < BaseEnum
      Customer::FINALIZE_ZERO_AMOUNT_INVOICE_OPTIONS.each do |type|
        value type
      end
    end
  end
end
