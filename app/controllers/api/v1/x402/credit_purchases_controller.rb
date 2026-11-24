# frozen_string_literal: true

module Api
  module V1
    module X402
      class CreditPurchasesController < BaseController
        RAW_FIELDS = %w[payment payment_requirements idempotency_key mode settle_response verify_response].freeze

        filter_audit_log_params! :idempotency_key

        def create
          result = ::X402::CreditPurchases::PurchaseService.call(
            organization: current_organization,
            params: create_params.to_h.deep_symbolize_keys.merge(raw_purchase_params)
          )

          if result.success?
            render(json: ::V1::X402::SettlementSerializer.new(result.settlement, root_name: "x402_settlement", replayed: result.replayed))
          else
            render_error_response(result)
          end
        end

        private

        def create_params
          params.expect(credit_purchase: [:connection_code, :plan_code, :wallet_code, wallet: {}])
        end

        def raw_purchase_params
          body = JSON.parse(request.raw_post)
          purchase = body["credit_purchase"] if body.is_a?(Hash)

          if purchase.is_a?(Hash)
            purchase.slice(*RAW_FIELDS).symbolize_keys
          else
            {}
          end
        rescue JSON::ParserError
          {}
        end

        def resource_name
          "x402"
        end
      end
    end
  end
end
