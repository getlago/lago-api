# frozen_string_literal: true

module Queries
  class OrderFormsQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:status).maybe do
        value(:string, included_in?: OrderForm::STATUSES.keys.map(&:to_s)) |
          array(:string, included_in?: OrderForm::STATUSES.keys.map(&:to_s))
      end
      optional(:external_customer_id).maybe(:string)
    end
  end
end
