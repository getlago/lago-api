# frozen_string_literal: true

module Coupons
  class DestroyService < BaseService
    def initialize(coupon:)
      @coupon = coupon
      super
    end

    def call
      return result.not_found_failure!(resource: 'coupon') unless coupon

      ActiveRecord::Base.transaction do
        coupon.discard!
        coupon.coupon_targets.discard_all

        coupon.applied_coupons.active.each do |applied_coupon|
          AppliedCoupons::TerminateService.call(applied_coupon:)
        end
      end

      result.coupon = coupon
      result
    end

    private

    attr_reader :coupon
  end
end
