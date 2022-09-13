# frozen_string_literal: true

module Api
  module V1
    class CouponsController < Api::BaseController
      def create
        service = Coupons::CreateService.new
        result = service.create(
          **input_params
            .merge(organization_id: current_organization.id)
            .to_h
            .symbolize_keys,
        )

        if result.success?
          render_coupon(result.coupon)
        else
          validation_errors(result)
        end
      end

      def update
        service = Coupons::UpdateService.new
        result = service.update_from_api(
          organization: current_organization,
          code: params[:code],
          params: input_params,
        )

        if result.success?
          render_coupon(result.coupon)
        else
          render_error_response(result)
        end
      end

      def destroy
        service = Coupons::DestroyService.new
        result = service.destroy_from_api(
          organization: current_organization,
          code: params[:code],
        )

        if result.success?
          render_coupon(result.coupon)
        else
          render_error_response(result)
        end
      end

      def show
        coupon = current_organization.coupons.find_by(
          code: params[:code],
        )

        return not_found_error(resource: 'coupon') unless coupon

        render_coupon(coupon)
      end

      def index
        coupons = current_organization.coupons
          .order(created_at: :desc)
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            coupons,
            ::V1::CouponSerializer,
            collection_name: 'coupons',
            meta: pagination_metadata(coupons),
          ),
        )
      end

      private

      def input_params
        params.require(:coupon).permit(
          :name,
          :code,
          :amount_cents,
          :amount_currency,
          :expiration,
          :expiration_duration,
        )
      end

      def render_coupon(coupon)
        render(
          json: ::V1::CouponSerializer.new(
            coupon,
            root_name: 'coupon',
          ),
        )
      end
    end
  end
end
