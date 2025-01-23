# frozen_string_literal: true

module Queries
  class CustomersQueryFiltersContract < Dry::Validation::Contract
    params do
      required(:filters).hash do
        optional(:account_type).array(:string, included_in?: Customer::ACCOUNT_TYPES.values)
      end

      optional(:search_term).maybe(:string)
    end
  end
end
