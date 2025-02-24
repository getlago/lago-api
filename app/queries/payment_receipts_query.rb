# frozen_string_literal: true

class PaymentReceiptsQuery < BaseQuery
  def call
    return result unless validate_filters.success?

    payment_receipts = apply_filters(base_scope)
    payment_receipts = paginate(payment_receipts)
    payment_receipts = apply_consistent_ordering(payment_receipts)

    result.payment_receipts = payment_receipts
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::PaymentReceiptsQueryFiltersContract.new
  end

  def base_scope
    PaymentReceipt.for_organization(organization)
  end

  def apply_filters(scope)
    scope = filter_by_invoice(scope) if filters.invoice_id.present?
    scope
  end

  def filter_by_invoice(scope)
    invoice_id = filters.invoice_id

    scope.joins(<<~SQL)
      LEFT JOIN invoices_payment_requests ON (invoices_payment_requests.payment_request_id = payment_requests.id)
    SQL
      .where("invoices.id = :invoice_id OR invoices_payment_requests.invoice_id = :invoice_id", invoice_id:)
  end
end
