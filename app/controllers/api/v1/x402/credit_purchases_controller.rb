# frozen_string_literal: true

module Api
  module V1
    module X402
      class CreditPurchasesController < BaseController
        def create
          result = ::X402::CreditPurchases::PurchaseService.call(organization: current_organization, params: create_params.to_h)

          if result.success?
            render(json: ::V1::X402::SettlementSerializer.new(result.settlement, root_name: "x402_settlement"))
          else
            render_error_response(result)
          end
        end

        private

        # The payment and its requirements are opaque x402 objects, forwarded unchanged (D7).
        def create_params
          params.require(:credit_purchase).permit(:connection_code, :wallet_code, :plan_code, payment: {}, payment_requirements: {}, wallet: {})
        end
      end
    end
  end
end
