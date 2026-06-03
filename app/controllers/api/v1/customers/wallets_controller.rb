# frozen_string_literal: true

module Api
  module V1
    module Customers
      class WalletsController < BaseController
        include WalletActions

        def create
          wallet_create(customer)
        end

        def update
          wallet = customer.wallets.find_by(code: params[:code])

          wallet_update(wallet)
        end

        def terminate
          wallet = customer.wallets.find_by(code: params[:code])

          wallet_terminate(wallet)
        end

        def show
          wallet = customer.wallets.find_by(code: params[:code])

          wallet_show(wallet)
        end

        def index
          permitted_params = params.permit(:currency, :billing_entity_code, billing_entity_codes: [])
          billing_entity_codes = (
            Array.wrap(permitted_params[:billing_entity_codes]) +
            Array.wrap(permitted_params[:billing_entity_code])
          ).compact_blank.uniq.presence
          wallet_index(
            external_customer_id: customer.external_id,
            currency: permitted_params[:currency],
            billing_entity_codes: billing_entity_codes
          )
        end

        private

        def resource_name
          "wallet"
        end
      end
    end
  end
end
