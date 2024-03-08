# frozen_string_literal: true

class AddNewIndexToGroups < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :groups, %w[billable_metric_id parent_group_id]
  end
end
