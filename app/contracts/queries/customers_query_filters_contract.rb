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
      end

      optional(:search_term).maybe(:string)
    end
  end
end
