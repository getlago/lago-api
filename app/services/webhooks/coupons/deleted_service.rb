# frozen_string_literal: true

module Webhooks
  module Coupons
    class DeletedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::CouponSerializer.new(
          object,
          root_name: "coupon"
        )
      end

      def webhook_type
        "coupon.deleted"
      end

      def object_type
        "coupon"
      end
    end
  end
end
