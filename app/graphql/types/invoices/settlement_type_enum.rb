# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Invoices
    class SettlementTypeEnum < Types::BaseEnum
      graphql_name "InvoiceSettlementTypeEnum"

      # we only have settlements for credit notes for now
      value InvoiceSettlement::SETTLEMENT_TYPES.fetch(:credit_note)
    end
  end
end
