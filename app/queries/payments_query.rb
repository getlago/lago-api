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

  def base_scope
    invoices_join = ActiveRecord::Base.sanitize_sql_array(
      ["LEFT JOIN invoices AS i ON i.id = payments.payable_id AND payments.payable_type = 'Invoice' AND i.organization_id = ?", organization]
    )
    payment_requests_join = ActiveRecord::Base.sanitize_sql_array(
      ["LEFT JOIN payment_requests AS pr ON pr.id = payments.payable_id AND payments.payable_type = 'PaymentRequest' AND pr.organization_id = ?", organization]
    )
    invoices_payment_requests_join = ActiveRecord::Base.sanitize_sql_array(
      ["LEFT JOIN invoices_payment_requests AS ipr ON ipr.payment_request_id = pr.id"]
    )

    Payment.joins(invoices_join)
      .joins(payment_requests_join)
      .joins(invoices_payment_requests_join)
      .where('i.id IS NOT NULL OR pr.id IS NOT NULL')
  end

  def filter_by_invoice(scope)
    invoice_id = filters.invoice_id
    scope.where('i.id = :invoice_id OR ipr.invoice_id = :invoice_id', invoice_id:)
  end
end
