# frozen_string_literal: true

class AddDeletedAtToPlans < ActiveRecord::Migration[7.0]
  def change
    add_column :plans, :deleted_at, :datetime

    safety_assured do
      add_index :plans, :deleted_at

      remove_index :plans, %i[code organization_id]
      add_index :plans, %i[organization_id code], unique: true, where: 'deleted_at IS NULL'
    end
  end
end
