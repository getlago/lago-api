# frozen_string_literal: true

class AddVoidedAtToCreditNotes < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_notes, :voided_at, :datetime
  end
end
