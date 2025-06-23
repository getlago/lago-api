# frozen_string_literal: true

class CreatePlansTaxes < ActiveRecord::Migration[7.0]
  def change
    create_table :plans_taxes, id: :uuid do |t|
      t.references :plan, type: :uuid, null: false, foreign_key: true, index: true
      t.references :tax, type: :uuid, null: false, foreign_key: true, index: true

      t.timestamps
    end
  end
end
