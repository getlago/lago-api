# frozen_string_literal: true

module Api
  module V1
    module Customers
      class AppliedCouponsController < Api::BaseController
        def destroy
          customer = current_organization.customers.find_by(external_id: params[:customer_external_id])
          return not_found_error(resource: "customer") unless customer

          applied_coupon = customer.applied_coupons.find_by(id: params[:id])
          return not_found_error(resource: "applied_coupon") unless applied_coupon

          result = ::AppliedCoupons::TerminateService.call(applied_coupon:)
          if result.success?
            render(json: ::V1::AppliedCouponSerializer.new(result.applied_coupon, root_name: "applied_coupon"))
          else
            render_error_response(result)
          end
        end
      end
    end
  end
end
