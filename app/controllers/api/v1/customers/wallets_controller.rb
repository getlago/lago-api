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
          wallet_index(external_customer_id: customer.external_id)
        end

        private

        def resource_name
          "wallet"
        end
      end
    end
  end
end
