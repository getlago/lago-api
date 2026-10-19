# frozen_string_literal: true

module Api
  module V2
    # Only checkout_url is routed here; the other customer endpoints stay on the v1 fallback.
    class CustomersController < Api::V2::BaseController
      def checkout_url
        customer = current_organization.customers.find_by(external_id: params[:customer_external_id])

        result = ::Customers::GenerateCheckoutUrlService.call(customer:)

        if result.success?
          render(
            json: ::V1::PaymentProviders::CustomerCheckoutSerializer.new(
              customer,
              root_name: "customer",
              checkout_url: result.checkout_url
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def resource_name
        "customer"
      end
    end
  end
end
