# frozen_string_literal: true

class RenameCreditNotesVatFields < ActiveRecord::Migration[7.0]
  def up
    add_column :credit_notes, :taxes_rate, :float, null: false, default: 0.0
    safety_assured do
      rename_column :credit_notes, :vat_amount_cents, :taxes_amount_cents
      rename_column :credit_notes, :precise_vat_amount_cents, :precise_taxes_amount_cents
      remove_column :credit_notes, :vat_amount_currency
    end
  end

  def down
    remove_column :credit_notes, :taxes_rate
    rename_column :credit_notes, :taxes_amount_cents, :vat_amount_cents
    rename_column :credit_notes, :precise_taxes_amount_cents, :precise_vat_amount_cents
    add_column :credit_notes, :vat_amount_currency

    execute <<-SQL
      UPDATE credit_notes
      SET vat_amount_currency = balance_amount_currency
    SQL
  end
end
