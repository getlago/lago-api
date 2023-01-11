# frozen_string_literal: true

class CustomerInvoicesQuery < BaseQuery
  def call(customer_id:, search_term:, status:, page:, limit:)
    @search_term = search_term

    invoices = base_scope(customer_id:).result
    invoices = invoices.where(status:) if status.present?
    invoices = invoices.order(created_at: :desc).page(page).per(limit)

    result.invoices = invoices
    result
  end

  private

  attr_reader :search_term

  def base_scope(customer_id:)
    Customer.find(customer_id).invoices.ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {
      m: 'or',
      id_cont: search_term,
      number_cont: search_term,
    }
  end
end
