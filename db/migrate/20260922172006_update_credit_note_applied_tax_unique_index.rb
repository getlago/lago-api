# frozen_string_literal: true

class UpdateCreditNoteAppliedTaxUniqueIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  OLD_INDEX = "index_credit_notes_taxes_on_credit_note_id_and_tax_code"
  NEW_INDEX = "index_credit_notes_taxes_on_note_id_code_rate"

  def up
    add_index :credit_notes_taxes, %i[credit_note_id tax_code tax_rate],
      unique: true, name: NEW_INDEX, algorithm: :concurrently, if_not_exists: true
    remove_index :credit_notes_taxes, name: OLD_INDEX, algorithm: :concurrently, if_exists: true
  end

  # NOTE: once a credit note holds two rates under the same tax code, which is what this index
  #       change allows, the old (credit_note_id, tax_code) unique index cannot be rebuilt without
  #       deleting or merging credit note taxes, so there is no safe automatic rollback.
  def down
    raise ActiveRecord::IrreversibleMigration,
      "credit notes may now hold several rates under one tax code, which the previous unique index forbids"
  end
end
