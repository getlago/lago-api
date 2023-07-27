# frozen_string_literal: true

class CreateAddOnsTaxes < ActiveRecord::Migration[7.0]
  def change
    create_table :add_ons_taxes, id: :uuid do |t|
      t.references :add_on, type: :uuid, null: false, foreign_key: true, index: true
      t.references :tax, type: :uuid, null: false, foreign_key: true, index: true

      t.timestamps
    end
  end
end
