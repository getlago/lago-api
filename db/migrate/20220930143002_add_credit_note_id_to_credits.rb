# frozen_string_literal: true

class AddCreditNoteIdToCredits < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_reference :credits, :credit_notes, type: :uuid, null: true, foreign_key: true, index: true
      change_column_null :credits, :applied_coupon_id, null: true
    end
  end
end
