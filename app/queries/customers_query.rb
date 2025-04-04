# frozen_string_literal: true

class CustomersQuery < BaseQuery
  Result = BaseResult[:customers]

  def call
    return result unless validate_filters.success?

    customers = base_scope.result
    customers = paginate(customers)
    customers = apply_consistent_ordering(customers)

    customers = with_account_type(customers) if filters.account_type.present?
    customers = with_billing_entity_ids(customers) if filters.billing_entity_ids.present?
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
end
