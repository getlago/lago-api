# frozen_string_literal: true

class InvoicesQuery < BaseQuery
  def call
    invoices = base_scope.result.includes(:customer)
    invoices = paginate(invoices)
    invoices = invoices.order(issuing_date: :desc, created_at: :desc)

    invoices = with_currency(invoices) if filters.currency
    invoices = with_customer_external_id(invoices) if filters.customer_external_id
    invoices = with_customer_id(invoices) if filters.customer_id.present?
    invoices = with_invoice_type(invoices) if filters.invoice_type.present?
    invoices = with_issuing_date_range(invoices) if filters.issuing_date_from || filters.issuing_date_to
    invoices = with_status(invoices) if filters.status.present?
    invoices = with_payment_status(invoices) if filters.payment_status.present?
    invoices = with_payment_dispute_lost(invoices) unless filters.payment_dispute_lost.nil?
    invoices = with_payment_overdue(invoices) unless filters.payment_overdue.nil?

    result.invoices = invoices
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def base_scope
    organization.invoices.visible.ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    terms = {
      m: 'or',
      id_cont: search_term,
      number_cont: search_term
    }
    return terms if filters.customer_id.present?

    terms.merge(
      customer_name_cont: search_term,
      customer_external_id_cont: search_term,
      customer_email_cont: search_term
    )
  end

  def with_currency(scope)
    scope.where(currency: filters.currency)
  end

  def with_customer_external_id(scope)
    scope.joins(:customer).where(customer: {external_id: filters.customer_external_id})
  end

  def with_customer_id(scope)
    scope.where(customer_id: filters.customer_id)
  end

  def with_invoice_type(scope)
    scope.where(invoice_type: filters.invoice_type)
  end

  def with_status(scope)
    scope.where(status: filters.status)
  end

  def with_payment_status(scope)
    scope.where(payment_status: filters.payment_status)
  end

  def with_payment_dispute_lost(scope)
    if filters.payment_dispute_lost
      scope.where.not(payment_dispute_lost_at: nil)
    else
      scope.where(payment_dispute_lost_at: nil)
    end
  end

  def with_payment_overdue(scope)
    scope.where(payment_overdue: filters.payment_overdue)
  end

  def with_issuing_date_range(scope)
    scope = scope.where(issuing_date: issuing_date_from..) if filters.issuing_date_from
    scope = scope.where(issuing_date: ..issuing_date_to) if filters.issuing_date_to
    scope
  end

  def issuing_date_from
    @issuing_date_from ||= parse_datetime_filter(:issuing_date_from)
  end

  def issuing_date_to
    @issuing_date_to ||= parse_datetime_filter(:issuing_date_to)
  end
end
