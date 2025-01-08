# frozen_string_literal: true

class PaymentsQuery < BaseQuery
  def call
    pp Payment.for_organization(organization).to_sql
    payments = Payment.for_organization(organization)
    payments = paginate(payments)
    payments = apply_consistent_ordering(payments)

    result.payments = payments
    result
  end
end
