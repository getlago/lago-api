# frozen_string_literal: true

class CreateProductItems < ActiveRecord::Migration[7.0]
  def change
    create_table :product_items, id: :uuid do |t|
      t.references :product, type: :uuid, foreign_key: true, index: true
      t.references :billable_metric, type: :uuid, foreign_key: true, index: true

      t.timestamps
    end
  end
end
