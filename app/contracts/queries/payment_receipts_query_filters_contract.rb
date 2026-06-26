# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Queries
  class PaymentReceiptsQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:invoice_id).maybe(:string, format?: Regex::UUID)
    end
  end
end
