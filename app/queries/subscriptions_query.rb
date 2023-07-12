# frozen_string_literal: true

class SubscriptionsQuery < BaseQuery
  def call
    subscriptions = paginate(organization.subscriptions)
    subscriptions = with_status(subscriptions) if filters.status.present? && valid_status?
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

  def with_status(scope)
    scope.where(status: filters.status)
  end

  def valid_status?
    filters.status.all? { |s| Subscription.statuses.key?(s) }
  end
end
