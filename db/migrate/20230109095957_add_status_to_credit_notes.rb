# frozen_string_literal: true

class AddStatusToCreditNotes < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_notes, :status, :integer, null: false, default: 1
  end
end
