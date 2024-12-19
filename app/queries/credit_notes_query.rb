# frozen_string_literal: true

class CreditNotesQuery < BaseQuery
  def call
    credit_notes = base_scope.result
    credit_notes = paginate(credit_notes)
    credit_notes = apply_consistent_ordering(credit_notes)

    credit_notes = with_currency(credit_notes) if filters.currency.present?
    credit_notes = with_customer_external_id(credit_notes) if filters.customer_external_id
    credit_notes = with_customer_id(credit_notes) if filters.customer_id.present?
    credit_notes = with_reason(credit_notes) if filters.reason.present?
    credit_notes = with_credit_status(credit_notes) if filters.credit_status.present?
    credit_notes = with_refund_status(credit_notes) if filters.refund_status.present?
    credit_notes = with_invoice_number(credit_notes) if filters.invoice_number.present?
    credit_notes = with_issuing_date_range(credit_notes) if filters.issuing_date_from || filters.issuing_date_to
    credit_notes = with_amount_range(credit_notes) if filters.amount_from.present? || filters.amount_to.present?

    result.credit_notes = credit_notes
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def base_scope
    CreditNote
      .includes(:customer)
      .joins(:customer)
      .where('customers.organization_id = ?', organization.id)
      .finalized
      .ransack(search_params)
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
      customer_firstname_cont: search_term,
      customer_lastname_cont: search_term,
      customer_external_id_cont: search_term,
      customer_email_cont: search_term
    )
  end

  def with_currency(scope)
    scope.where(total_amount_currency: filters.currency)
  end

  def with_customer_external_id(scope)
    scope.joins(:customer).where(customers: {external_id: filters.customer_external_id})
  end

  def with_customer_id(scope)
    scope.where(customer_id: filters.customer_id)
  end

  def with_reason(scope)
    scope.where(reason: filters.reason)
  end

  def with_credit_status(scope)
    scope.where(credit_status: filters.credit_status)
  end

  def with_refund_status(scope)
    scope.where(refund_status: filters.refund_status)
  end

  def with_invoice_number(scope)
    scope.joins(:invoice).where(invoices: {number: filters.invoice_number})
  end

  def with_issuing_date_range(scope)
    scope = scope.where(issuing_date: issuing_date_from..) if filters.issuing_date_from
    scope = scope.where(issuing_date: ..issuing_date_to) if filters.issuing_date_to
    scope
  end

  def with_amount_range(scope)
    scope = scope.where("total_amount_cents >= ?", filters.amount_from) if filters.amount_from
    scope = scope.where("total_amount_cents <= ?", filters.amount_to) if filters.amount_to
    scope
  end

  def issuing_date_from
    @issuing_date_from ||= parse_datetime_filter(:issuing_date_from)
  end

  def issuing_date_to
    @issuing_date_to ||= parse_datetime_filter(:issuing_date_to)
  end
end
