# frozen_string_literal: true

class AddPreciseAmountCentsToCreditNoteItems < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_note_items, :precise_amount_cents, :decimal, precision: 30, scale: 5

    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE credit_note_items SET precise_amount_cents = amount_cents;
          SQL
        end
      end

      change_column_null :credit_note_items, :precise_amount_cents, false
    end
  end
end
