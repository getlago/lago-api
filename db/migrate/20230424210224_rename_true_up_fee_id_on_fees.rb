# frozen_string_literal: true

class RenameTrueUpFeeIdOnFees < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_column :fees, :true_up_fee_id, :true_up_parent_fee_id
    end
  end
end
