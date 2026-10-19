# frozen_string_literal: true

module Api
  module V2
    module Customers
      class PaymentMethodsController < BaseController
        cursor_paginated_index(PaymentMethod)
        serializable_with ::V2::PaymentMethodSerializer

        def index
          result = ::PaymentMethodsQuery.call(
            organization: current_organization,
            pagination: cursor,
            filters: {external_customer_id: customer.external_id}
          )

          if result.success?
            render_payment_methods(result.payment_methods.preload(::V2::PaymentMethodSerializer::PRELOADS))
          else
            render_error_response(result)
          end
        end

        def destroy
          result = ::PaymentMethods::DestroyService.call(
            payment_method: customer.payment_methods.find_by(id: params[:id])
          )

          if result.success?
            render_payment_method(result.payment_method)
          else
            render_error_response(result)
          end
        end

        def set_as_default
          payment_method = customer.payment_methods.find_by(id: params[:id])
          return not_found_error(resource: "payment_method") unless payment_method

          result = ::PaymentMethods::SetAsDefaultService.call(payment_method:)

          if result.success?
            render_payment_method(result.payment_method)
          else
            render_error_response(result)
          end
        end

        private

        def resource_name
          "payment_method"
        end
      end
    end
  end
end
