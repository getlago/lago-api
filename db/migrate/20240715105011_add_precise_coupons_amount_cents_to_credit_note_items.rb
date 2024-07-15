# frozen_string_literal: true

class AddPreciseCouponsAmountCentsToCreditNoteItems < ActiveRecord::Migration[7.1]
  def change
    add_column :credit_note_items,
      :precise_coupons_amount_cents,
      :decimal,
      precision: 30,
      scale: 5,
      null: false,
      default: 0
  end
end
