# frozen_string_literal: true

class UpdateCreditNotes < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_column :credit_notes, :status, :credit_status
      rename_column :credit_notes, :amount_cents, :credit_amount_cents
      rename_column :credit_notes, :amount_currency, :credit_amount_currency
      rename_column :credit_notes, :remaining_amount_cents, :balance_amount_cents
      rename_column :credit_notes, :remaining_amount_currency, :balance_amount_currency

      change_table :credit_notes, bulk: true do |t|
        t.bigint :total_amount_cents, null: false, default: 0

        # NOTE: Disable rubocop comment as table is not used in production yet
        t.string :total_amount_currency, null: false
      end
    end
  end
end
