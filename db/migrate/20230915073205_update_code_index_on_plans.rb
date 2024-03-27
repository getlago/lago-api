# frozen_string_literal: true

class UpdateCodeIndexOnPlans < ActiveRecord::Migration[7.0]
  def change
    remove_index :plans, %i[organization_id code]

    add_index :plans,
      %i[organization_id code],
      unique: true,
      where: "deleted_at IS NULL AND parent_id IS NULL"
  end
end
