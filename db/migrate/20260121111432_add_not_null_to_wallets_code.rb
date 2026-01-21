# frozen_string_literal: true

class AddNotNullToWalletsCode < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      change_column_null :wallets, :code, false
    end
  end
end
