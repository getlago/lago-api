# frozen_string_literal: true

class ValidateBalanceCheckConstraintsToWallets < ActiveRecord::Migration[8.0]
  def change
    validate_check_constraint :wallets, name: "check_balance_cents_non_negative_when_traceable"
    validate_check_constraint :wallets, name: "check_credits_balance_non_negative_when_traceable"
  end
end
