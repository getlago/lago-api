# frozen_string_literal: true

class AddPriorityToWallets < ActiveRecord::Migration[8.0]
  def change
    add_column :wallets, :priority, :integer # nullable, no default
  end
end
