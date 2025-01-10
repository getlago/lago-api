# frozen_string_literal: true

class PaymentsQuery < BaseQuery
  def call
    return result unless validate_filters.success?
    payments = base_scope
    payments = paginate(payments)
    payments = apply_consistent_ordering(payments)
    payments = filter_by_invoice(payments) if filters.invoice_id.present?

    result.payments = payments
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::PaymentsQueryFiltersContract.new
  end

  def base_scope
    Payment.for_organization(organization)
  end

  def filter_by_invoice(scope)
    invoice_id = filters.invoice_id

    invoices_payment_requests_join = <<~SQL
      LEFT JOIN invoices_payment_requests ON invoices_payment_requests.payment_request_id = payment_requests.id
    SQL
    scope.joins(invoices_payment_requests_join)
      .where('invoices.id = :invoice_id OR invoices_payment_requests.invoice_id = :invoice_id', invoice_id: invoice_id)
  end
end
