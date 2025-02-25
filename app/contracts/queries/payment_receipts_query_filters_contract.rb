# frozen_string_literal: true

module Queries
  class PaymentReceiptsQueryFiltersContract < Dry::Validation::Contract
    UUID_REGEX = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

    params do
      required(:filters).hash do
        optional(:invoice_id).maybe(:string, format?: UUID_REGEX)
      end
    end
  end
end
