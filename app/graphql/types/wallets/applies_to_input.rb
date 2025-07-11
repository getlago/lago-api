# frozen_string_literal: true

module Types
  module Wallets
    class AppliesToInput < BaseInputObject
      argument :fee_types, [Types::Fees::TypesEnum], required: false
      argument :billable_metric_ids, [ID], required: false
    end
  end
end
