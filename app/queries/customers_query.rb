# frozen_string_literal: true

class CustomersQuery < BaseQuery
  def call
    customers = base_scope.result
    customers = paginate(customers)
    customers = apply_consistent_ordering(customers)

    result.customers = customers
    result
  end

  private

  def base_scope
    Customer.where(organization:).where(additional_params).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: 'or',
      name_cont: search_term,
      firstname_cont: search_term,
      lastname_cont: search_term,
      legal_name_cont: search_term,
      external_id_cont: search_term,
      email_cont: search_term
    }
  end
end
