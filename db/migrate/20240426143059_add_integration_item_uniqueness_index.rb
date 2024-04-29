# frozen_string_literal: true

class AddIntegrationItemUniquenessIndex < ActiveRecord::Migration[7.0]
  def change
    add_index :integration_items, [:external_id, :integration_id], unique: true
  end
end
