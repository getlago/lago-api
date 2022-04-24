# frozen_string_literal: true

class AddFieldNameToBillableMetrics < ActiveRecord::Migration[7.0]
  def change
    add_column :billable_metrics, :field_name, :string, null: true
  end
end
