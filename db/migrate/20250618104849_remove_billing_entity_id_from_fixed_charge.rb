# frozen_string_literal: true

class RemoveBillingEntityIdFromFixedCharge < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      remove_column :fixed_charges, :billing_entity_id
    end
  end
end
