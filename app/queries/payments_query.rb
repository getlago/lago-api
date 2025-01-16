# frozen_string_literal: true

class PaymentsQuery < BaseQuery
  def call
    return result unless validate_filters.success?

    payments = apply_filters(base_scope)
    payments = paginate(payments)
    payments = apply_consistent_ordering(payments)

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

  def apply_filters(scope)
    scope = filter_by_invoice(scope) if filters.invoice_id.present?
    scope = filter_by_customer(scope) if filters.external_customer_id.present?
    scope
  end

  def filter_by_customer(scope)
    external_customer_id = filters.external_customer_id

    scope.joins(<<~SQL)
      LEFT JOIN customers ON 
        (payments.payable_type = 'Invoice' AND customers.id = invoices.customer_id) OR 
        (payments.payable_type = 'PaymentRequest' AND customers.id = payment_requests.customer_id)
    SQL
      .where('customers.external_id = :external_customer_id', external_customer_id:)
  end

  def filter_by_invoice(scope)
    invoice_id = filters.invoice_id

    scope.joins(<<~SQL)
      LEFT JOIN invoices_payment_requests 
      ON invoices_payment_requests.payment_request_id = payment_requests.id
    SQL
      .where('invoices.id = :invoice_id OR invoices_payment_requests.invoice_id = :invoice_id', invoice_id:)
  end
end
