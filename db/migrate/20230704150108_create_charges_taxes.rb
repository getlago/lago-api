# frozen_string_literal: true

class CreateChargesTaxes < ActiveRecord::Migration[7.0]
  def change
    create_table :charges_taxes, id: :uuid do |t|
      t.references :charge, type: :uuid, null: false, foreign_key: true, index: true
      t.references :tax, type: :uuid, null: false, foreign_key: true, index: true

      t.timestamps
    end
  end
end
