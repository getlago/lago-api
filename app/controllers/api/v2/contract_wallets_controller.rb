# frozen_string_literal: true

module Api
  module V2
    class ContractWalletsController < Api::V2::BaseController
      include Api::RequiresCatalogWallets
      include Api::V2::ContractLookup

      cursor_paginated_index(CatalogWallet)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::ContractWalletSerializer

      def show
        contract_wallet = find_contract_wallet

        return not_found_error(resource: "contract_wallet") unless contract_wallet

        render_contract_wallet(contract_wallet)
      end

      def index
        contract = find_contract(params[:contract_external_id])
        return not_found_error(resource: "contract") unless contract

        result = ::ContractWalletsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: {contract_id: contract.id, **date_range_filters}
        )

        if result.success?
          render_contract_wallets(result.contract_wallets.preload(::V2::ContractWalletSerializer::PRELOADS))
        else
          render_error_response(result)
        end
      end

      private

      def find_contract_wallet
        contract = find_contract(params[:contract_external_id])
        contract&.wallets&.find_by(code: params[:code])
      end

      def resource_name
        "contract_wallet"
      end
    end
  end
end
