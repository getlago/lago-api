# frozen_string_literal: true

class ValidateWalletsBillingEntitiesForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :wallets, :billing_entities
  end
end
