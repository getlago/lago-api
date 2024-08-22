# frozen_string_literal: true

class AddMissingChargeFilterIdRelations < ActiveRecord::Migration[7.0]
  def change
    add_column :quantified_events, :charge_filter_id, :uuid, null: true
    safety_assured do
      add_index :quantified_events, :charge_filter_id
    end

    add_column :adjusted_fees, :charge_filter_id, :uuid, null: true
    safety_assured do
      add_index :adjusted_fees, :charge_filter_id
    end
  end
end
