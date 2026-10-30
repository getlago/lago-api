# frozen_string_literal: true

class BillingEntitiesQuery < BaseQuery
  Result = BaseResult[:billing_entities]

  def call
    result.billing_entities = paginate(apply_consistent_ordering(organization.billing_entities))
    result
  end
end
