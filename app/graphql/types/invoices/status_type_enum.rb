# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Invoices
    class StatusTypeEnum < Types::BaseEnum
      graphql_name "InvoiceStatusTypeEnum"

      Invoice::STATUS.keys.each do |type|
        value type
      end
    end
  end
end
