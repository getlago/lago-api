# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Invoices
    class InvoiceTypeEnum < Types::BaseEnum
      Invoice::INVOICE_TYPES.each do |type|
        value type
      end
    end
  end
end
