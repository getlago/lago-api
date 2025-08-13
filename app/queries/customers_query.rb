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
    active_subscriptions_count = "COUNT(CASE WHEN subscriptions.status = 1 THEN 1 END)"
    count_scope = scope.left_joins(:subscriptions).group("customers.id")

    count_scope = if filters.active_subscriptions_count_from == filters.active_subscriptions_count_to
      count_scope.having("#{active_subscriptions_count} = ?", filters.active_subscriptions_count_from)
    elsif filters.active_subscriptions_count_from.present? && filters.active_subscriptions_count_to.nil?
      count_scope.having("#{active_subscriptions_count} > ?", filters.active_subscriptions_count_from)
    elsif filters.active_subscriptions_count_from.nil? && filters.active_subscriptions_count_to.present?
      count_scope.having("#{active_subscriptions_count} < ?", filters.active_subscriptions_count_to)
    else
      count_scope.having("#{active_subscriptions_count} BETWEEN ? AND ?", filters.active_subscriptions_count_from, filters.active_subscriptions_count_to)
    end

    scope.where(id: count_scope.pluck(:id))
  end
end
