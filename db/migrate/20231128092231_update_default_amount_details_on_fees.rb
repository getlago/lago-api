# frozen_string_literal: true

class UpdateDefaultAmountDetailsOnFees < ActiveRecord::Migration[7.0]
  def change
    change_column_default :fees, :amount_details, from: '{}', to: {}
  end
end
