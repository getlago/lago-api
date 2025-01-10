# frozen_string_literal: true

module Queries
  class PaymentsQueryFiltersContract < Dry::Validation::Contract
    params do
      required(:filters).hash do
        optional(:invoice_id).maybe(:string)
        optional(:external_customer_id).maybe(:string)
      end
    end

    rule(filters: :invoice_id) do
      next if value.blank? # Skip validation for nil or empty values
      key.failure('must be a valid UUID') unless valid_uuid?(value)
    end

    private

    def valid_uuid?(uuid)
      uuid =~ /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/
    end
  end
end
