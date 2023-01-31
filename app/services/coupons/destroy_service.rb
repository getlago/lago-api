# frozen_string_literal: true

module Coupons
  class DestroyService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(coupon:)
      @coupon = coupon
      super
    end

    def call
      return result.not_found_failure!(resource: 'coupon') unless coupon
      return result.not_allowed_failure!(code: 'attached_to_an_active_customer') unless coupon.deletable?

      coupon.destroy!

      result.coupon = coupon
      result
    end

    private

    attr_reader :coupon
  end
end
