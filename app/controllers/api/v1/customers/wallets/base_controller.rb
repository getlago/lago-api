# frozen_string_literal: true

module Api
  module V1
    module Customers
      module Wallets
        class BaseController < Api::V1::Customers::BaseController
          before_action :find_wallet

          private

          attr_reader :wallet

          def find_wallet
            # TODO: Once wallet `code` attribute is added, retrieve wallet by code instead of id
            # @wallet = customer.wallets.find_by!(code: params[:wallet_code])
            @wallet = customer.wallets.find_by!(id: params[:wallet_id])
          rescue ActiveRecord::RecordNotFound
            not_found_error(resource: "wallet")
          end
        end
      end
    end
  end
end
