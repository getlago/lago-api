# frozen_string_literal: true

class AddBaseAmountCentsToCreditNotesAppliedTaxes < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_notes_taxes, :base_amount_cents, :bigint, null: false, default: 0
  end
end
