# frozen_string_literal: true

class SubscriptionsQuery < BaseQuery
  Result = BaseResult[:subscriptions]
  Filters = BaseFilters[:external_customer_id, :plan_code, :status, :customer, :overriden, :exclude_next_subscriptions]

  def call
    subscriptions = base_scope.result
    subscriptions = paginate(subscriptions)
    # FE pulls next_subscription through Graphql object, which creates additional cases to handle when
    # next_subscription should be excluded from the result to avoid duplicates.
    subscriptions = with_excluded_next_subscriptions(subscriptions) if filters.exclude_next_subscriptions
    subscriptions = subscriptions.where(status: filtered_statuses) if valid_status?
    subscriptions = apply_consistent_ordering(
      subscriptions,
      default_order: <<~SQL.squish
        subscriptions.subscription_at DESC NULLS LAST,
        subscriptions.created_at DESC
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
    scope.joins(:plan).where(plans: {code: filters.plan_code})
  end

  def with_overriden(scope)
    if filters.overriden
      scope.joins(:plan).where.not(plans: {parent_id: nil})
    else
      scope.joins(:plan).where(plans: {parent_id: nil})
    end
  end

  def with_excluded_next_subscriptions(scope)
    # If there is a status filter and statuses of previous subscription and next subscritpion do not match,
    # previous subscription can be filtered out, while next subscription should be included.
    prev_sub_excluded_next_included_in_statuses_clause = ""
    if filters.status.present?
      status_values = filters.status.map { |s| Subscription.statuses[s] }
      prev_sub_excluded_next_included_in_statuses_clause = "OR prev_subscriptions.status NOT IN (#{status_values.join(",")}) AND subscriptions.status IN (#{status_values.join(",")})"
    end
    # FE does not show next sub for terminated subscriptions, so we need to include them in the query.
    prev_sub_terminated_clause = "OR prev_subscriptions.status = #{Subscription.statuses[:terminated]}"
    # FE does not show next canceled subscription, so it should be included
    next_sub_canceled_clause = "OR subscriptions.status = #{Subscription.statuses[:canceled]}"

    scope.joins("LEFT JOIN subscriptions AS prev_subscriptions ON subscriptions.previous_subscription_id = prev_subscriptions.id")
      .where("subscriptions.previous_subscription_id IS NULL #{prev_sub_terminated_clause} #{prev_sub_excluded_next_included_in_statuses_clause} #{next_sub_canceled_clause}")
  end

  def filtered_statuses
    filters.status
  end

  def valid_status?
    filters.status.present? && filters.status.all? { |s| Subscription.statuses.key?(s) }
  end
end
