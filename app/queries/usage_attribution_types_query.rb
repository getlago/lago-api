# frozen_string_literal: true

class UsageAttributionTypesQuery < BaseQuery
  Result = BaseResult[:usage_attribution_types]
  Filters = BaseFilters[:role, :roots]

  def call
    return result unless validate_filters.success?

    usage_attribution_types = base_scope.result.preload(:parent)
    usage_attribution_types = with_role(usage_attribution_types) if filters.role.present?
    usage_attribution_types = only_roots(usage_attribution_types) if filters.roots

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

  # Roots carry the whole tree through `children`, so paginating them keeps
  # every subtree intact — unlike paginating the flat list, which would split a
  # parent from its descendants across pages.
  # A type whose parent has been discarded counts as a root too.
  def only_roots(scope)
    scope.where(
      "usage_attribution_types.parent_id IS NULL OR usage_attribution_types.parent_id NOT IN (?)",
      UsageAttributionType.where(organization:).select(:id)
    )
  end
end
