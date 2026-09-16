# frozen_string_literal: true

class SetEventsAutovacuumAnalyzeThreshold < ActiveRecord::Migration[8.0]
  def up
    # The global analyze scale factor puts the trigger more than a year out on a table this size,
    # letting statistics fall behind the data.
    safety_assured do
      execute <<~SQL
        ALTER TABLE events SET (
          autovacuum_analyze_scale_factor = 0,
          autovacuum_analyze_threshold = 50000
        );
      SQL
    end
  end

  def down
    # RESET keeps the dump byte-identical and leaves autovacuum_vacuum_scale_factor alone.
    safety_assured do
      execute <<~SQL
        ALTER TABLE events RESET (
          autovacuum_analyze_scale_factor,
          autovacuum_analyze_threshold
        );
      SQL
    end
  end
end
