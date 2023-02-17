# frozen_string_literal: true

module Api
  module V1
    class AppliedCouponsController < Api::BaseController
      def create
        customer = Customer.find_by(
          external_id: create_params[:external_customer_id],
          organization_id: current_organization.id,
        )

        coupon = Coupon.find_by(
          code: create_params[:coupon_code],
          organization_id: current_organization.id,
        )

        result = AppliedCoupons::CreateService.call(customer:, coupon:, params: create_params)

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

      def index
        applied_coupons = current_organization.applied_coupons
        if params[:external_customer_id]
          applied_coupons =
            applied_coupons.joins(:customer).where(customers: { external_id: params[:external_customer_id] })
        end
        applied_coupons = applied_coupons.where(status: params[:status]) if valid_status?(params[:status])
        applied_coupons = applied_coupons.order(created_at: :desc)
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            applied_coupons,
            ::V1::AppliedCouponSerializer,
            collection_name: 'applied_coupons',
            meta: pagination_metadata(applied_coupons),
          ),
        )
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

      def valid_status?(status)
        AppliedCoupon.statuses.key?(status)
      end
    end
  end
end
