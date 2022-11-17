# frozen_string_literal: true

class AddUniqueIndexOnCustomersExternalId < ActiveRecord::Migration[7.0]
  def change
    remove_index :customers, :external_id
    add_index :customers, [:external_id, :organization_id], unique: true
  end
end
