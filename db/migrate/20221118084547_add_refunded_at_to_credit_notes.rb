# frozen_string_literal: true

class AddRefundedAtToCreditNotes < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_notes, :refunded_at, :datetime, null: true
  end
end
