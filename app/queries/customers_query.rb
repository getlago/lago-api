# frozen_string_literal: true

class CustomersQuery < BaseQuery
  Result = BaseResult[:customers]
  Filters = BaseFilters[
    :organization_id,
    :account_type,
    :billing_entity_ids,
    :with_deleted,
    :active_subscriptions_count_from,
    :active_subscriptions_count_to,
    :countries,
    :states,
    :zipcodes,
    :currencies,
    :has_tax_identification_number,
    :metadata
  ]

  def call
    return result unless validate_filters.success?

    customers = base_scope.result
    customers = paginate(customers)
    customers = apply_consistent_ordering(customers)

    customers = with_account_type(customers) if filters.account_type.present?
    customers = with_billing_entity_ids(customers) if filters.billing_entity_ids.present?
    customers = with_active_subscriptions_range(customers) if filters.active_subscriptions_count_from.present? || filters.active_subscriptions_count_to.present?
    customers = with_billing_address_filter(customers) if billing_address_filter?
    customers = with_currencies(customers) if filters.currencies.present?
    customers = with_has_tax_identification_number(customers) if filters.key?(:has_tax_identification_number)
    customers = with_metadata(customers) if filters.metadata.present?

    customers = customers.with_discarded if filters.with_deleted

    result.customers = customers
    result
  end

  private

  def billing_address_filter?
    filters.countries.present? || filters.states.present? || filters.zipcodes.present?
  end

  def filters_contract
    @filters_contract ||= Queries::CustomersQueryFiltersContract.new
  end

  def base_scope
    Customer.where(organization:).ransack(search_params)
  end

  def with_currencies(scope)
    scope.where(currency: filters.currencies)
  end

  def with_billing_address_filter(scope)
    scope = scope.where(country: filters.countries) if filters.countries.present?
    scope = scope.where(state: filters.states) if filters.states.present?
    scope = scope.where(zipcode: filters.zipcodes) if filters.zipcodes.present?
    scope
  end

  def with_metadata(scope)
    presence_filters, absence_filters = filters.metadata.partition { |_k, v| v.present? }

    if presence_filters.any?
      tuples = presence_filters.map { "(?, ?)" }.join(", ")
      subquery = Metadata::CustomerMetadata
        .where("(key, value) IN (#{tuples})", *presence_filters.flatten)
        .group("customer_id")
        .having("COUNT(DISTINCT key) = ?", presence_filters.size)
        .select(:customer_id)

      scope = scope.where(id: subquery)
    end

    if absence_filters.any?
      keys = absence_filters.map { |k, _v| k }
      subquery = Metadata::CustomerMetadata.where(key: keys).select(:customer_id)
      scope = scope.where.not(id: subquery)
    end

    scope
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

  def with_has_tax_identification_number(scope)
    if ActiveModel::Type::Boolean.new.cast(filters.has_tax_identification_number)
      scope.where.not(tax_identification_number: nil)
    else
      scope.where(tax_identification_number: nil)
    end
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
