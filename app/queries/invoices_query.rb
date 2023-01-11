# frozen_string_literal: true

class InvoicesQuery < BaseQuery
  def call(search_term:, status:, payment_status:, page:, limit:, filters: {}) # rubocop:disable Metrics/ParameterLists
    @search_term = search_term

    invoices = base_scope.result.includes(:customer)
    invoices = invoices.where(id: filters[:ids]) if filters[:ids].present?
    invoices = invoices.where(status:) if status.present?
    invoices = invoices.where(payment_status:) if payment_status.present?
    invoices = invoices.order(issuing_date: :desc, created_at: :desc).page(page).per(limit)

    result.invoices = invoices
    result
  end

  private

  attr_reader :search_term

  def base_scope
    organization.invoices.ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {
      m: 'or',
      id_cont: search_term,
      number_cont: search_term,
      customer_name_cont: search_term,
      customer_external_id_cont: search_term,
      customer_email_cont: search_term,
    }
  end
end
