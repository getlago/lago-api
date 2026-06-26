# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Queries
  class PaymentsQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:invoice_id).maybe(:string, format?: Regex::UUID)
      optional(:external_customer_id).maybe(:string)
    end
  end
end
