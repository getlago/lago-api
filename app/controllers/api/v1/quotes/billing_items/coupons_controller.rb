# frozen_string_literal: true

module Api
  module V1
    module Quotes
      module BillingItems
        class CouponsController < Api::BaseController
          def create
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::Coupons::AddService.call(quote:, params: create_params.to_h)
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          def update
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::Coupons::UpdateService.call(quote:, id: params[:id], params: update_params.to_h)
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          def destroy
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::Coupons::RemoveService.call(quote:, id: params[:id])
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          private

          def create_params
            params.require(:coupon).permit(
              :coupon_id,
              :coupon_type,
              :amount_cents,
              :percentage_rate,
              :currency,
              :frequency,
              :frequency_duration,
              :expiration_at,
              :position
            )
          end

          def update_params
            params.require(:coupon).permit(
              :coupon_id,
              :coupon_type,
              :amount_cents,
              :percentage_rate,
              :currency,
              :frequency,
              :frequency_duration,
              :expiration_at,
              :position
            )
          end

          def render_quote(quote)
            render(json: ::V1::QuoteSerializer.new(quote, root_name: "quote").serialize)
          end

          def resource_name
            "quote"
          end
        end
      end
    end
  end
end
