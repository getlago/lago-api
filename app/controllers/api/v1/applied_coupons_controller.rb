# frozen_string_literal: true

module Api
  module V1
    class AppliedCouponsController < Api::BaseController
      def create
        service = AppliedCoupons::CreateService.new
        result = service.create_from_api(
          organization: current_organization,
          args: create_params,
        )

        if result.success?
          render(
            json: ::V1::AppliedCouponSerializer.new(
              result.applied_coupon,
              root_name: 'applied_coupon',
            ),
          )
        else
          validation_errors(result)
        end
      end

      private

      def create_params
        params.require(:applied_coupon).permit(
          :customer_id,
          :coupon_code,
          :amount_cents,
          :amount_currency,
        )
      end
    end
  end
end
