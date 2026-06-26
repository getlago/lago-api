# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Wallets
    class AppliesToInput < BaseInputObject
      argument :billable_metric_ids, [ID], required: false
      argument :fee_types, [Types::Fees::TypesEnum], required: false
    end
  end
end
