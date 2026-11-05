# frozen_string_literal: true

module Api
  module V2
    module Invoices
      class PaymentUrlsController < Api::V2::BaseController
        serializable_with ::V2::Invoices::PaymentUrlSerializer, root: :payment_url

        # The Stripe service raises a rate limit, as v1 and GraphQL expect. Not a refusal: v2 asks the
        # client to retry, without the payment failure webhook.
        rescue_from ::Stripe::RateLimitError, with: :stripe_rate_limit_error

        def create
          invoice = current_organization.invoices.visible.product_catalog.find_by(id: params[:id])
          return not_found_error(resource: "invoice") unless invoice

          result = ::Invoices::Payments::GeneratePaymentUrlService.call(invoice:)

          if result.success?
            render_payment_url(::V2::Invoices::PaymentUrlSerializer::PaymentUrl.new(invoice:, url: result.payment_url))
          else
            render_error_response(result)
          end
        end

        private

        def resource_name
          "invoice"
        end

        def stripe_rate_limit_error(error)
          render_error_response(BaseResult.new.too_many_provider_requests_failure!(provider_name: "stripe", error:))
        end
      end
    end
  end
end
