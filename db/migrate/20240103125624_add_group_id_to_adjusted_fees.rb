# frozen_string_literal: true

class AddGroupIdToAdjustedFees < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_reference :adjusted_fees, :group, type: :uuid, null: true, index: true, foreign_key: true
    end
  end
end
