# frozen_string_literal: true

class AddEventsValidationIndex < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :events, %i[organization_id code created_at], where: "deleted_at IS NULL"
  end
end
