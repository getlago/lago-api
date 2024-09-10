class UpdateIndexesForCreditNotesTaxes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    remove_index :credit_notes_taxes, %i[credit_note_id tax_id], unique: true, algorithm: :concurrently

    add_index :credit_notes_taxes, :tax_code, algorithm: :concurrently
    add_index :credit_notes_taxes, %i[credit_note_id tax_code], unique: true, algorithm: :concurrently
  end
end
