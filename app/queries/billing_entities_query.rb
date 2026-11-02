# frozen_string_literal: true

class BillingEntitiesQuery < BaseQuery
  Result = BaseResult[:billing_entities]
  Filters = BaseFilters[:created_at_from, :created_at_to]

  def call
    billing_entities = with_date_range(organization.billing_entities, :created_at)

    result.billing_entities = paginate(apply_consistent_ordering(billing_entities))
    result
  rescue BaseService::FailedResult
    result
  end
end
