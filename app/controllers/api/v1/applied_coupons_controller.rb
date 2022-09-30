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
          render_error_response(result)
        end
      end

      private

      def create_params
        params.require(:applied_coupon).permit(
          :external_customer_id,
          :coupon_code,
          :frequency,
          :frequency_duration,
          :amount_cents,
          :amount_currency,
          :percentage_rate,
        )
      end
    end
  end
end
