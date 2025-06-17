# frozen_string_literal: true

class AddForeignKeyConstraintToCreditNoteIdAtWalletTransaction < ActiveRecord::Migration[7.1]
  def change
    add_foreign_key :wallet_transactions, :credit_notes, validate: false
  end
end
