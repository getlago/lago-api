# frozen_string_literal: true

class InvoicesQuery < BaseQuery
  def call(search_term:, page:, limit:, filters: {}, payment_overdue: nil)
    @search_term = search_term
    @customer_id = filters[:customer_id]
    @filters = filters

    invoices = base_scope.result.includes(:customer)
    invoices = invoices.where(currency: filters[:currency]) if filters[:currency]
    invoices = with_customer_external_id(invoices) if filters[:customer_external_id]
    invoices = invoices.where(customer_id: filters[:customer_id]) if filters[:customer_id].present?
    invoices = invoices.where(invoice_type: filters[:invoice_type]) if filters[:invoice_type]
    invoices = with_issuing_date_range(invoices) if filters[:issuing_date_from] || filters[:issuing_date_to]
    invoices = invoices.where(status: filters[:status]) if filters[:status].present?
    invoices = invoices.where(payment_status: filters[:payment_status]) if filters[:payment_status].present?
    invoices = invoices.where.not(payment_dispute_lost_at: nil) if filters[:payment_dispute_lost]
    invoices = invoices.where(payment_overdue:) if payment_overdue.present?
    invoices = invoices.order(issuing_date: :desc, created_at: :desc).page(page).per(limit)

    result.invoices = invoices
    result
  rescue BaseService::FailedResult
    result
  end

  private

  attr_reader :search_term, :filters

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

  def with_customer_external_id(scope)
    scope.joins(:customer).where(customer: {external_id: filters[:customer_external_id]})
  end

  def with_issuing_date_range(scope)
    scope = scope.where(issuing_date: issuing_date_from..) if filters[:issuing_date_from]
    scope = scope.where(issuing_date: ..issuing_date_to) if filters[:issuing_date_to]
    scope
  end

  def issuing_date_from
    @issuing_date_from ||= parse_datetime_filter(:issuing_date_from)
  end

  def issuing_date_to
    @issuing_date_to ||= parse_datetime_filter(:issuing_date_to)
  end
end
