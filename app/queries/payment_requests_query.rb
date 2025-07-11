# frozen_string_literal: true

class PaymentRequestsQuery < BaseQuery
  Result = BaseResult[:payment_requests]
  Filters = BaseFilters[:external_customer_id, :payment_status]

  def call
    payment_requests = PaymentRequest.where(organization:)

    payment_requests = with_external_customer(payment_requests) if filters.external_customer_id
    payment_requests = with_payment_status(payment_requests) if filters.payment_status

    payment_requests = apply_consistent_ordering(payment_requests)
    payment_requests = paginate(payment_requests)
    result.payment_requests = payment_requests
    result
  end

  private

  def with_external_customer(scope)
    scope.joins(:customer).where(customers: {external_id: filters.external_customer_id})
  end

  def with_payment_status(scope)
    scope.where(payment_status: filters.payment_status)
  end
end
