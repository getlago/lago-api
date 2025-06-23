# frozen_string_literal: true

class AddExpressionToBillableMetric < ActiveRecord::Migration[7.1]
  def change
    add_column :billable_metrics, :expression, :string
  end
end
