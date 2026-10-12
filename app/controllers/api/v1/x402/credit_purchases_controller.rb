# frozen_string_literal: true

module Api
  module V1
    module X402
      class CreditPurchasesController < BaseController
        def create
          result = ::X402::CreditPurchases::PurchaseService.call(
            organization: current_organization,
            params: create_params.to_h.deep_symbolize_keys.merge(signed_payment_params)
          )

          if result.success?
            render(json: ::V1::X402::SettlementSerializer.new(result.settlement, root_name: "x402_settlement", replayed: result.replayed))
          else
            render_error_response(result)
          end
        end

        private

        def create_params
          params.require(:credit_purchase).permit(:connection_code, :plan_code, :wallet_code, wallet: {})
        end

        def signed_payment_params
          body = JSON.parse(request.raw_post)
          purchase = body["credit_purchase"] if body.is_a?(Hash)

          if purchase.is_a?(Hash)
            {payment: purchase["payment"], payment_requirements: purchase["payment_requirements"]}
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
