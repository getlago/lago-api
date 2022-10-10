# frozen_string_literal: true

class RenameCreditCreditNote < ActiveRecord::Migration[7.0]
  def change
    rename_column :credits, :credit_notes_id, :credit_note_id
  end
end
