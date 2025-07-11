# frozen_string_literal: true

module Types
  module Wallets
    class AppliesTo < Types::BaseObject
      graphql_name "WalletAppliesTo"

      field :fee_types, [Types::Fees::TypesEnum], null: true, method: :allowed_fee_types
      field :billable_metrics, [Types::BillableMetrics::Object]
    end
  end
end
