# frozen_string_literal: true

class AddBalanceCheckConstraintsToWallets < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :wallets,
      "(traceable = false OR balance_cents >= 0)",
      name: "check_balance_cents_non_negative_when_traceable",
      validate: false

    add_check_constraint :wallets,
      "(traceable = false OR credits_balance >= 0)",
      name: "check_credits_balance_non_negative_when_traceable",
      validate: false
  end
end
