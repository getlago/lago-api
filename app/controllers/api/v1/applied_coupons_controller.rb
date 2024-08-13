# frozen_string_literal: true

module Api
  module V1
    class AppliedCouponsController < Api::BaseController
      def create
        customer = Customer.find_by(
          external_id: create_params[:external_customer_id],
          organization_id: current_organization.id
        )

        coupon = Coupon.find_by(
          code: create_params[:coupon_code],
          organization_id: current_organization.id
        )

        result = AppliedCoupons::CreateService.call(customer:, coupon:, params: create_params)

        if result.success?
          render(
            json: ::V1::AppliedCouponSerializer.new(
              result.applied_coupon,
              root_name: 'applied_coupon'
            )
          )
        else
          render_error_response(result)
        end
      end

      def index
        result = AppliedCouponsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: index_filters
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.applied_coupons.includes(:credits),
              ::V1::AppliedCouponSerializer,
              collection_name: 'applied_coupons',
              meta: pagination_metadata(result.applied_coupons),
              includes: %i[credits]
            )
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
          :percentage_rate
        )
      end

      def index_filters
        params.permit(:external_customer_id, :status)
      end
    end
  end
end
