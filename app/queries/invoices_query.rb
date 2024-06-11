# frozen_string_literal: true

class InvoicesQuery < BaseQuery
  def call(search_term:, status:, page:, limit:, filters: {}, customer_id: nil, payment_status: nil, payment_dispute_lost: nil, payment_overdue: nil) # rubocop:disable Metrics/ParameterLists
    @search_term = search_term
    @customer_id = customer_id

    invoices = base_scope.result.includes(:customer)
    invoices = invoices.where(id: filters[:ids]) if filters[:ids].present?
    invoices = invoices.where(customer_id:) if customer_id.present?
    invoices = invoices.where(status:) if status.present?
    invoices = invoices.where(payment_status:) if payment_status.present?
    invoices = invoices.where.not(payment_dispute_lost_at: nil) unless payment_dispute_lost.nil?
    invoices = invoices.where(payment_overdue:) if payment_overdue.present?
    invoices = invoices.order(issuing_date: :desc, created_at: :desc).page(page).per(limit)

    result.invoices = invoices
    result
  end

  private

  attr_reader :search_term

  def base_scope
    organization.invoices.not_generating.ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    terms = {
      m: 'or',
      id_cont: search_term,
      number_cont: search_term
    }
    return terms if @customer_id.present?

    terms.merge(
      customer_name_cont: search_term,
      customer_external_id_cont: search_term,
      customer_email_cont: search_term
    )
  end
end
