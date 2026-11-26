# frozen_string_literal: true

module Api
  module V2
    module ContractWallets
      class TransactionsController < Api::V2::BaseController
        include Api::RequiresCatalogWallets
        include Api::V2::ContractLookup

        FILTERS = %i[direction status reason credit_allocation_code].freeze

        cursor_paginated_index(CatalogWalletTransaction)
        date_range_filtered_index(:created_at)
        serializable_with ::V2::ContractWalletTransactionSerializer, root: :wallet_transaction

        before_action :ensure_contract_wallet

        def index
          result = ::ContractWalletTransactionsQuery.call(
            organization: current_organization,
            pagination: cursor,
            filters: {contract_wallet_id: contract_wallet.id, **index_filters, **date_range_filters}
          )

          if result.success?
            render_wallet_transactions(result.wallet_transactions.preload(::V2::ContractWalletTransactionSerializer::PRELOADS))
          else
            render_error_response(result)
          end
        end

        def show
          wallet_transaction = contract_wallet.transactions.find_by(id: params[:id])

          return not_found_error(resource: "wallet_transaction") unless wallet_transaction

          render_wallet_transaction(wallet_transaction)
        end

        private

        def ensure_contract_wallet
          not_found_error(resource: "contract_wallet") unless contract_wallet
        end

        def contract_wallet
          return @contract_wallet if defined?(@contract_wallet)

          contract = find_contract(params[:contract_external_id])
          @contract_wallet = contract&.wallets&.find_by(code: params[:wallet_code])
        end

        # Read raw rather than permitted, so that a list or an object is a `value_is_invalid` error, not an
        # ignored filter.
        def index_filters
          FILTERS.index_with { params[it] }
        end

        def resource_name
          "wallet_transaction"
        end
      end
    end
  end
end
