# frozen_string_literal: true

module Queries
  class UsageAttributionTypesQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:role).maybe(:string, included_in?: UsageAttributionType::ROLES.values)
    end
  end
end
