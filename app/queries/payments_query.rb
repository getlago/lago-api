# frozen_string_literal: true

class PaymentsQuery < BaseQuery
  def call
    payments = base_scope
    payments = paginate(payments)
    payments = apply_consistent_ordering(payments)
    payments = filter_by_invoice(payments) if filters.invoice_id.present?

    result.payments = payments
    result
  end

  private

  def validate_invoice_id(invoice_id)
    unless valid_uuid?(invoice_id)
      result.single_validation_failure!(
        field: :invoice_id,
        error_code: 'value_is_invalid'
      )
    end
  end

  def valid_uuid?(uuid)
    !!(uuid =~ /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/)
  end

  def base_scope
    Payment.for_organization(organization)
  end

  def filter_by_invoice(scope)
    invoice_id = filters.invoice_id
    validate_invoice_id(invoice_id)

    invoices_payment_requests_join = <<~SQL
      LEFT JOIN invoices_payment_requests AS ipr ON ipr.payment_request_id = pr.id
    SQL

    scope.joins(invoices_payment_requests_join)
      .where('i.id = :invoice_id OR ipr.invoice_id = :invoice_id', invoice_id:)
  end
end
