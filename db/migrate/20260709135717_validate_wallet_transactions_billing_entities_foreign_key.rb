# frozen_string_literal: true

class ValidateWalletTransactionsBillingEntitiesForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :wallet_transactions, :billing_entities
  end
end
