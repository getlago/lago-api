# frozen_string_literal: true

module Entitlement
  class FeaturesQuery < BaseQuery
    Result = BaseResult[:features]
    Filters = BaseFilters[:created_at_from, :created_at_to]

    def call
      features = base_scope.result
      features = apply_consistent_ordering(features)
      features = with_date_range(features, :created_at)

      result.features = paginate(features)
      result
    rescue BaseService::FailedResult
      result
    end

    private

    def base_scope
      Feature.where(organization:).ransack(search_params)
    end

    def search_params
      return if search_term.blank?

      {
        m: "or",
        name_cont: search_term,
        code_cont: search_term,
        description_cont: search_term
      }
    end
  end
end
