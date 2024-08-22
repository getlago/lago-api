# frozen_string_literal: true

class AddDeletedAtToBillableMetrics < ActiveRecord::Migration[7.0]
  def change
    add_column :billable_metrics, :deleted_at, :datetime
    add_column :charges, :deleted_at, :datetime
    add_column :groups, :deleted_at, :datetime
    add_column :group_properties, :deleted_at, :datetime
    add_column :events, :deleted_at, :datetime
    add_column :persisted_events, :deleted_at, :datetime

    safety_assured do
      add_index :billable_metrics, :deleted_at
      add_index :charges, :deleted_at
      add_index :groups, :deleted_at
      add_index :group_properties, :deleted_at
      add_index :events, :deleted_at
      add_index :persisted_events, :deleted_at

      remove_index :billable_metrics, %i[organization_id code]
      add_index :billable_metrics, %i[organization_id code], unique: true, where: 'deleted_at IS NULL'
    end
  end
end
