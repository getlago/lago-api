# frozen_string_literal: true

class AddItemCodeToIntegrationItems < ActiveRecord::Migration[8.0]
  def change
    add_column :integration_items, :item_code, :string
  end
end
