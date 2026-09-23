# frozen_string_literal: true

class UsageAttributionTypesQuery < BaseQuery
  Result = BaseResult[:usage_attribution_types]
  Filters = BaseFilters[:role]

  def call
    return result unless validate_filters.success?

    usage_attribution_types = base_scope.result.preload(:parent)
    usage_attribution_types = with_role(usage_attribution_types) if filters.role.present?

    usage_attribution_types = paginate(usage_attribution_types)
    usage_attribution_types = apply_consistent_ordering(usage_attribution_types)

    result.usage_attribution_types = usage_attribution_types
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::UsageAttributionTypesQueryFiltersContract.new
  end

  def base_scope
    UsageAttributionType.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      code_cont: search_term,
      name_cont: search_term
    }
  end

  def with_role(scope)
    scope.where(role: filters.role)
  end
end
