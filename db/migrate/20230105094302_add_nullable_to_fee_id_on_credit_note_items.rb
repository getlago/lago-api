# frozen_string_literal: true

class AddNullableToFeeIdOnCreditNoteItems < ActiveRecord::Migration[7.0]
  def change
    change_column_null :credit_note_items, :fee_id, true
  end
end
