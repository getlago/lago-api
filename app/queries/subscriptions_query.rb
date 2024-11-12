# frozen_string_literal: true

class SubscriptionsQuery < BaseQuery
  def call
    subscriptions = paginate(organization.subscriptions)
    subscriptions = subscriptions.where(status: filtered_statuses)
    subscriptions = subscriptions.order("subscriptions.started_at ASC NULLS LAST, subscriptions.created_at ASC")

    subscriptions = with_external_customer(subscriptions) if filters.external_customer_id
    subscriptions = with_plan_code(subscriptions) if filters.plan_code

    result.subscriptions = subscriptions
    result
  end

  def with_external_customer(scope)
    scope.joins(:customer).where(customers: {external_id: filters.external_customer_id})
  end

  def with_plan_code(scope)
    scope.joins(:plan).where(plans: {code: filters.plan_code})
  end

  def filtered_statuses
    return [:active] unless valid_status?

    filters.status
  end

  def valid_status?
    filters.status.present? && filters.status.all? { |s| Subscription.statuses.key?(s) }
  end
end
