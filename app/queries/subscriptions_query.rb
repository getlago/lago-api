# frozen_string_literal: true

class SubscriptionsQuery < BaseQuery
  Result = BaseResult[:subscriptions]
  Filters = BaseFilters[:external_customer_id, :plan_code, :status, :customer, :overriden, :exclude_next_subscriptions]

  def call
    subscriptions = base_scope.result
    subscriptions = paginate(subscriptions)
    subscriptions = with_excluded_next_subscriptions(subscriptions) if filters.exclude_next_subscriptions
    subscriptions = subscriptions.where(status: filtered_statuses) if valid_status?
    subscriptions = apply_consistent_ordering(
      subscriptions,
      default_order: <<~SQL.squish
        subscriptions.subscription_at DESC NULLS LAST,
        subscriptions.created_at ASC
      SQL
    )

    subscriptions = with_external_customer(subscriptions) if filters.external_customer_id
    subscriptions = with_plan_code(subscriptions) if filters.plan_code
    subscriptions = with_overriden(subscriptions) unless filters.overriden.nil?

    result.subscriptions = subscriptions
    result
  end

  def base_scope
    if organization.present?
      Subscription.where(organization:)
    else
      Subscription.where(customer: filters.customer)
    end.joins(:customer, :plan).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    terms = {
      m: "or",
      id_cont: search_term,
      name_cont: search_term,
      external_id_cont: search_term,
      plan_name_cont: search_term,
      plan_code_cont: search_term
    }

    return terms if filters.external_customer_id.present?

    terms.merge(
      customer_name_cont: search_term,
      customer_firstname_cont: search_term,
      customer_lastname_cont: search_term,
      customer_external_id_cont: search_term,
      customer_email_cont: search_term
    )
  end

  def with_external_customer(scope)
    scope.joins(:customer).where(customers: {external_id: filters.external_customer_id})
  end

  def with_plan_code(scope)
    scope.joins(:plan).where(plan: {code: filters.plan_code})
  end

  def with_overriden(scope)
    if filters.overriden
      scope.joins(:plan).where.not(plan: {parent_id: nil})
    else
      scope.joins(:plan).where(plan: {parent_id: nil})
    end
  end

  def with_excluded_next_subscriptions(scope)
    if filters.status.blank?
      scope.where(previous_subscription_id: nil)
    else
      # Next subscription is included in previous by graphql object, but if their statuses do not match, previous
      # subscription can be filtered out, while next subscription is not.
      status_values = filters.status.map { |s| Subscription.statuses[s] }
      scope.joins("LEFT JOIN subscriptions AS prev_subscriptions ON subscriptions.previous_subscription_id = prev_subscriptions.id")
        .where("subscriptions.previous_subscription_id IS NULL OR (prev_subscriptions.status NOT IN (#{status_values.join(",")}) AND subscriptions.status IN (#{status_values.join(",")}))")
    end
  end

  def filtered_statuses
    filters.status
  end

  def valid_status?
    filters.status.present? && filters.status.all? { |s| Subscription.statuses.key?(s) }
  end
end
