# frozen_string_literal: true

class SubscriptionsQuery < BaseQuery
  Result = BaseResult[:subscriptions]
  Filters = BaseFilters[:external_customer_id, :plan_code, :status, :customer]

  def call
    subscriptions = base_scope.result
    subscriptions = paginate(subscriptions)
    subscriptions = subscriptions.where(status: filtered_statuses)
    subscriptions = apply_consistent_ordering(
      subscriptions,
      default_order: <<~SQL.squish
        subscriptions.started_at ASC NULLS LAST,
        subscriptions.created_at ASC
      SQL
    )

    subscriptions = with_external_customer(subscriptions) if filters.external_customer_id
    subscriptions = with_plan_code(subscriptions) if filters.plan_code

    result.subscriptions = subscriptions
    result
  end

  def base_scope
    if organization.present?
      Subscription.where(organization:)
    else
      Subscription.where(customer: filters.customer)
    end.joins(:customer, :plan)
      .ransack(search_params:)
  end

  def search_params
    return if search_term.blank?

    terms = {
      m: "or",
      id_cont: search_term,
      name_cont: search_term,
      external_id_cont: search_term
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

  def filtered_statuses
    return [:active] unless valid_status?

    filters.status
  end

  def valid_status?
    filters.status.present? && filters.status.all? { |s| Subscription.statuses.key?(s) }
  end
end
