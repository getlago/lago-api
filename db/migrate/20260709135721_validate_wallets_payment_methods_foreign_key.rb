# frozen_string_literal: true

class ValidateWalletsPaymentMethodsForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :wallets, :payment_methods
  end
end
