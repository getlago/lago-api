# frozen_string_literal: true

class CustomersQuery < BaseQuery
  def call(search_term:, page:, limit:, filters: {})
    @search_term = search_term

    customers = base_scope.result
    customers = customers.where(id: filters[:ids]) if filters[:ids].present?
    customers = customers.order(created_at: :desc).page(page).per(limit)

    result.customers = customers
    result
  end

  private

  attr_reader :search_term

  def base_scope
    Customer.where(organization:).ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {
      m: 'or',
      name_cont: search_term,
      external_id_cont: search_term,
      email_cont: search_term
    }
  end
end
