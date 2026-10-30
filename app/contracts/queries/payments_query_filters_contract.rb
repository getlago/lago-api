# frozen_string_literal: true

module Queries
  class PaymentsQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:invoice_id).maybe(:string, format?: Regex::UUID)
      optional(:external_customer_id).maybe(:string)
      optional(:customer_id).maybe(:string, format?: Regex::UUID)
    end
  end
end
