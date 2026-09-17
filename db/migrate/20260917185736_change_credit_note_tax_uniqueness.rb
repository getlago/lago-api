# frozen_string_literal: true

class ChangeCreditNoteTaxUniqueness < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_index :credit_notes_taxes, [:credit_note_id, :tax_id],
      unique: true,
      where: "tax_id IS NOT NULL",
      name: "index_credit_notes_taxes_on_credit_note_id_and_tax_id",
      algorithm: :concurrently

    add_index :credit_notes_taxes, [:credit_note_id, :tax_code, :tax_rate, :tax_description],
      unique: true,
      nulls_not_distinct: true,
      where: "tax_id IS NULL",
      name: "index_credit_notes_taxes_on_tax_identity",
      algorithm: :concurrently

    remove_index :credit_notes_taxes,
      name: "index_credit_notes_taxes_on_credit_note_id_and_tax_code",
      algorithm: :concurrently
  end

  def down
    add_index :credit_notes_taxes, [:credit_note_id, :tax_code],
      unique: true,
      name: "index_credit_notes_taxes_on_credit_note_id_and_tax_code",
      algorithm: :concurrently

    remove_index :credit_notes_taxes,
      name: "index_credit_notes_taxes_on_credit_note_id_and_tax_id",
      algorithm: :concurrently

    remove_index :credit_notes_taxes,
      name: "index_credit_notes_taxes_on_tax_identity",
      algorithm: :concurrently
  end
end
