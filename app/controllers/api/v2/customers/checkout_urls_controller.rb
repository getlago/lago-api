# frozen_string_literal: true

module Api
  module V2
    module Customers
      class CheckoutUrlsController < BaseController
        serializable_with ::V2::Customers::CheckoutUrlSerializer, root: :checkout_url

        def create
          result = ::Customers::GenerateCheckoutUrlService.call(customer:)

          if result.success?
            render_checkout_url(::V2::Customers::CheckoutUrlSerializer::CheckoutUrl.new(customer:, url: result.checkout_url))
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
end
