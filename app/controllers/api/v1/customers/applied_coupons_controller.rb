# frozen_string_literal: true

module Api
  module V1
    module Customers
      class AppliedCouponsController < BaseController
        def index
          result = AppliedCouponsQuery.call(
            organization: current_organization,
            pagination: {
              page: params[:page],
              limit: params[:per_page] || PER_PAGE
            },
            filters: params.permit(:status, coupon_code: []).merge(external_customer_id: customer.external_id)
          )

          if result.success?
            render(
              json: ::CollectionSerializer.new(
                result.applied_coupons.includes(:credits, :coupon, :customer),
                ::V1::AppliedCouponSerializer,
                collection_name: "applied_coupons",
                meta: pagination_metadata(result.applied_coupons),
                includes: %i[credits]
              )
            )
          else
            render_error_response(result)
          end
        end

        def destroy
          applied_coupon = customer.applied_coupons.find_by(id: params[:id])
          return not_found_error(resource: "applied_coupon") unless applied_coupon

          result = ::AppliedCoupons::TerminateService.call(applied_coupon:)
          if result.success?
            render(json: ::V1::AppliedCouponSerializer.new(result.applied_coupon, root_name: "applied_coupon"))
          else
            render_error_response(result)
          end
        end

        private

        def resource_name
          "applied_coupon"
        end
      end
    end
  end
end
