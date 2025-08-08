# frozen_string_literal: true

class CustomersQuery < BaseQuery
  Result = BaseResult[:customers]
  Filters = BaseFilters[
    :organization_id,
    :account_type,
    :billing_entity_ids,
    :with_deleted,
    :active_subscriptions_count_from,
    :active_subscriptions_count_to
  ]

  def call
    return result unless validate_filters.success?

    customers = base_scope.result
    customers = paginate(customers)
    customers = apply_consistent_ordering(customers)

    customers = with_account_type(customers) if filters.account_type.present?
    customers = with_billing_entity_ids(customers) if filters.billing_entity_ids.present?
    customers = with_active_subscriptions_range(customers) if filters.active_subscriptions_count_from.present? || filters.active_subscriptions_count_to.present?
    customers = customers.with_discarded if filters.with_deleted

    result.customers = customers
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::CustomersQueryFiltersContract.new
  end

  def base_scope
    Customer.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      firstname_cont: search_term,
      lastname_cont: search_term,
      legal_name_cont: search_term,
      external_id_cont: search_term,
      email_cont: search_term
    }
  end

  def with_account_type(scope)
    scope.where(account_type: filters.account_type)
  end

  def with_billing_entity_ids(scope)
    scope.where(billing_entity_id: filters.billing_entity_ids)
  end

  def with_active_subscriptions_range(scope)
    count_scope = scope.joins(:subscriptions).where(subscriptions: {status: "active"}).group("customers.id")
    count_scope = count_scope.having("COUNT(subscriptions.id) >= ?", filters.active_subscriptions_count_from) if filters.active_subscriptions_count_from
    count_scope = count_scope.having("COUNT(subscriptions.id) <= ?", filters.active_subscriptions_count_to) if filters.active_subscriptions_count_to

    scope.where(id: count_scope.pluck(:id))
  end
end
