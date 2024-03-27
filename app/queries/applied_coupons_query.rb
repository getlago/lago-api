# frozen_string_literal: true

class AppliedCouponsQuery < BaseQuery
  def call
    applied_coupons = paginate(base_scope)
    applied_coupons = applied_coupons.order(created_at: :desc)

    applied_coupons = with_external_customer(applied_coupons) if filters.external_customer_id
    applied_coupons = with_status(applied_coupons) if valid_status?

    result.applied_coupons = applied_coupons
    result
  end

  def base_scope
    organization.applied_coupons
      .joins(:customer).where(customers: {deleted_at: nil})
  end

  def with_external_customer(scope)
    scope.where(customers: {external_id: filters.external_customer_id})
  end

  def with_status(scope)
    scope.where(status: filters.status)
  end

  def valid_status?
    AppliedCoupon.statuses.key?(filters.status)
  end
end
