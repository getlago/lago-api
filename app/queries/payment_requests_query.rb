# frozen_string_literal: true

class PaymentRequestsQuery < BaseQuery
  def call
    payment_requests = PaymentRequest.where(organization:)
    payment_requests = paginate(payment_requests)
    payment_requests = payment_requests.order(created_at: :desc)

    payment_requests = with_external_customer(payment_requests) if filters.external_customer_id

    result.payment_requests = payment_requests
    result
  end

  private

  def with_external_customer(scope)
    scope.joins(:customer).where(customers: {external_id: filters.external_customer_id})
  end
end
