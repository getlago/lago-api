# frozen_string_literal: true

module Api
  module V1
    module Customers
      class WalletsController < BaseController
        include WalletIndex

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
