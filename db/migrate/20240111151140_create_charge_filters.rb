# frozen_string_literal: true

class CreateChargeFilters < ActiveRecord::Migration[7.0]
  def change
    create_table :charge_filters, id: :uuid do |t|
      t.references :charge, null: false, foreign_key: true, type: :uuid, index: true
      t.jsonb :properties, null: false, default: {}

      t.timestamps

      t.datetime :deleted_at, index: true
    end
  end
end
