# frozen_string_literal: true

class AddRoundingOptionsToBillableMetrics < ActiveRecord::Migration[7.1]
  def change
    create_enum :billable_metric_rounding_function, %w[round floor ceil]

    safety_assured do
      change_table :billable_metrics, bulk: true do |t|
        t.enum :rounding_function, enum_type: "billable_metric_rounding_function"
        t.integer :rounding_precision
      end
    end
  end
end
