# frozen_string_literal: true

class AddTrueUpFeeIdToFees < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_reference :fees, :true_up_fee, type: :uuid, null: true, index: true, foreign_key: {to_table: :fees}
    end
  end
end
