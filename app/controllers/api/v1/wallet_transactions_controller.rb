# frozen_string_literal: true

module Api
  module V1
    class WalletTransactionsController < Api::BaseController
      def create
        result = WalletTransactions::CreateFromParamsService.call(
          organization: current_organization,
          params: input_params
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.wallet_transactions,
              ::V1::WalletTransactionSerializer,
              collection_name: "wallet_transactions"
            )
          )
        else
          render_error_response(result)
        end
      end

      def index
        result = WalletTransactionsQuery.call(
          organization: current_organization,
          wallet_id: params[:id],
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {
            status: params[:status],
            transaction_type: params[:transaction_type]
          }
        )

        return render_error_response(result) unless result.success?

        render(
          json: ::CollectionSerializer.new(
            result.wallet_transactions,
            ::V1::WalletTransactionSerializer,
            collection_name: "wallet_transactions",
            meta: pagination_metadata(result.wallet_transactions)
          )
        )
      end

      def show
        wallet_transaction = current_organization.wallet_transactions.find_by(
          id: params[:id]
        )

        return not_found_error(resource: "wallet_transaction") unless wallet_transaction

        render(
          json: ::V1::WalletTransactionSerializer.new(
            wallet_transaction,
            root_name: "wallet_transaction"
          )
        )
      end

      private

      def input_params
        @input_params ||= params.require(:wallet_transaction).permit(
          :wallet_id,
          :paid_credits,
          :granted_credits,
          :voided_credits,
          :invoice_requires_successful_payment,
          metadata: [
            :key,
            :value
          ]
        )
      end

      def resource_name
        "wallet_transaction"
      end
    end
  end
end
