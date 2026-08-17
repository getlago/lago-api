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
          wallet_update(find_wallet)
        end

        def terminate
          wallet_terminate(find_wallet)
        end

        def show
          wallet_show(find_wallet)
        end

        def index
          permitted_params = params.permit(:currency, billing_entity_codes: [])
          wallet_index(
            external_customer_id: customer.external_id,
            currency: permitted_params[:currency],
            billing_entity_codes: permitted_params[:billing_entity_codes]
          )
        end

        private

        # Codes are only unique among active wallets, so a customer may own several
        # wallets sharing a code. Ordering by status resolves to the active one first.
        def find_wallet
          customer.wallets.order(:status).find_by(code: params[:code])
        end

        def resource_name
          "wallet"
        end
      end
    end
  end
end
