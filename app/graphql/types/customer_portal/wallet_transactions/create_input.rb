# frozen_string_literal: true

module Types
  module CustomerPortal
    module WalletTransactions
      class CreateInput < Types::BaseInputObject
        graphql_name "CreateCustomerPortalWalletTransactionInput"

        argument :paid_credits, String, required: false
        argument :purchase_order_number, String, required: false
        argument :wallet_id, ID, required: true
      end
    end
  end
end
