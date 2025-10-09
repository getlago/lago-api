# frozen_string_literal: true

class PaymentMethodsQuery < BaseQuery
  Result = BaseResult[:payment_methods]
  Filters = BaseFilters[:external_customer_id]

  def call
    payment_methods = base_scope
    payment_methods = with_external_customer(payment_methods) if filters.external_customer_id.present?

    payment_methods = apply_consistent_ordering(payment_methods)
    payment_methods = paginate(payment_methods)

    result.payment_methods = payment_methods
    result
  end

  private

  def with_external_customer(scope)
    scope.joins(:customer).where(customers: {external_id: filters.external_customer_id})
  end

  def base_scope
    PaymentMethod.where(organization:)
  end
end
