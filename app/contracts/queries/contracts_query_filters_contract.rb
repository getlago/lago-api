# frozen_string_literal: true

module Queries
  class ContractsQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:billing_entity_ids).maybe { array(:string, format?: Regex::UUID) }
    end
  end
end
