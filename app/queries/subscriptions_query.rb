# frozen_string_literal: true

class SubscriptionsQuery < BaseQuery
  def call
    subscriptions = paginate(organization.subscriptions.active)
    subscriptions = subscriptions.order(started_at: :asc)

    subscriptions = with_external_customer(subscriptions) if filters.external_customer_id
    subscriptions = with_plan_code(subscriptions) if filters.plan_code

    result.subscriptions = subscriptions
    result
  end

  def with_external_customer(scope)
    scope.joins(:customer).where(customers: { external_id: filters.external_customer_id })
  end

  def with_plan_code(scope)
    scope.joins(:plan).where(plans: { code: filters.plan_code })
  end
end
