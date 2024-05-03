# frozen_string_literal: true

class RemoveUniqueCountQuantifiedEvents < ActiveRecord::Migration[7.0]
  def up
    sql = <<~SQL
      DELETE FROM quantified_events
      WHERE billable_metric_id IN (
        SELECT id
        FROM billable_metrics
        WHERE aggregation_type = 3
      )
    SQL

    execute(sql)
  end

  def down
  end
end
