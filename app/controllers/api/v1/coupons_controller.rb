# frozen_string_literal: true

module Api
  module V1
    class CouponsController < Api::BaseController
      def assign
        service = AppliedCoupons::CreateService.new
        result = service.create_from_api(
          organization: current_organization,
          args: assign_params,
        )

        if result.success?
          render(
            json: ::V1::AppliedCouponSerializer.new(
              result.applied_coupon,
              root_name: 'coupon',
            ),
          )
        else
          validation_errors(result)
        end
      end

      private

      def assign_params
        params.require(:coupon).permit(
          :customer_id,
          :coupon_code,
          :amount_cents,
          :amount_currency,
        )
      end
    end
  end
end
