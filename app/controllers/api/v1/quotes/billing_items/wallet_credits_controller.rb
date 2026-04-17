# frozen_string_literal: true

module Api
  module V1
    module Quotes
      module BillingItems
        class WalletCreditsController < Api::BaseController
          def create
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::WalletCredits::AddService.call(quote:, params: create_params.to_h)
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          def update
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::WalletCredits::UpdateService.call(quote:, id: params[:id], params: update_params.to_h)
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          def destroy
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::WalletCredits::RemoveService.call(quote:, id: params[:id])
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          private

          def create_params
            params.require(:wallet_credit).permit(
              :name,
              :currency,
              :rate_amount,
              :paid_credits,
              :granted_credits,
              :expiration_at,
              :priority,
              :position,
              recurring_transaction_rules: [{}]
            )
          end

          def update_params
            params.require(:wallet_credit).permit(
              :name,
              :currency,
              :rate_amount,
              :paid_credits,
              :granted_credits,
              :expiration_at,
              :priority,
              :position,
              recurring_transaction_rules: [{}]
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
