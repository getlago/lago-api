# frozen_string_literal: true

class CouponsQuery < BaseQuery
  def call(search_term:, page:, limit:, status:, filters: {})
    @search_term = search_term

    coupons = base_scope.result
    coupons = coupons.where(id: filters[:ids]) if filters[:ids].present?
    coupons = coupons.where(status:) if status.present?
    coupons = coupons.order_by_status_and_expiration.page(page).per(limit)

    result.coupons = coupons
    result
  end

  private

  attr_reader :search_term

  def base_scope
    Coupon.where(organization:).ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      code_cont: search_term
    }
  end
end
