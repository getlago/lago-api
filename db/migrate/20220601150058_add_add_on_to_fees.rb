# frozen_string_literal: true

class AddAddOnToFees < ActiveRecord::Migration[7.0]
  def change
    add_reference :fees, :applied_add_on, type: :uuid, foreign_key: true, index: true
  end
end
