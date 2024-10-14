# frozen_string_literal: true

class AddReferenceToCreditNoteFromWalletTransaction < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_reference :wallet_transactions, :credit_note, type: :uuid, null: true, index: {algorithm: :concurrently}
  end
end
