# frozen_string_literal: true

class UpdateDefaultAmountDetailsOnFees < ActiveRecord::Migration[7.0]
  class Fee < ApplicationRecord; end

  def change
    change_column_default :fees, :amount_details, from: '{}', to: {}

    reversible do |dir|
      dir.up do
        # Update all existing fees with '{}' value to {}
        Fee.where(amount_details: '{}').update_all(amount_details: {})
      end
    end
  end
end
