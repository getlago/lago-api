# frozen_string_literal: true

module Queries
  class CustomersQueryFiltersContract < Dry::Validation::Contract
    params do
      required(:filters).hash do
        optional(:account_type).array(:string, included_in?: Customer::ACCOUNT_TYPES.values)
        optional(:billing_entity_ids).maybe { array(:string, format?: Regex::UUID) }
        optional(:countries).array(:string, included_in?: ISO3166::Country.codes)
        optional(:states).array(:string)
        optional(:zipcodes).array(:string)
        optional(:currencies).array(:string, included_in?: Customer.currency_list)
        optional(:has_tax_identification_number).value(:"coercible.string", included_in?: %w[true false])
        optional(:metadata).value(:hash)
        optional(:has_customer_type).value(:"coercible.string", included_in?: %w[true false])
        optional(:customer_type).value(:string, included_in?: Customer::CUSTOMER_TYPES.values)
      end

      optional(:search_term).maybe(:string)
    end

    rule("filters.metadata") do
      if key? && value.is_a?(Hash)
        value.each_with_index do |(k, v), index|
          key([:filters, :metadata]).failure("keys must be string") unless k.is_a?(String)
          key([:filters, :metadata, k]).failure("must be a string") unless v.is_a?(String)
        end
      end
    end

    rule("filters.has_customer_type", "filters.customer_type") do
      if values["filters.has_customer_type"] == "false" && values["filters.customer_type"].present?
        key([:filters, :customer_type]).failure("must be nil when has_customer_type is false")
      end
    end
  end
end
