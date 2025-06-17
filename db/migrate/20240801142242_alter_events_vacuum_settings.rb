# frozen_string_literal: true

class AlterEventsVacuumSettings < ActiveRecord::Migration[7.1]
  def up
    safety_assured do
      execute "ALTER TABLE events set (autovacuum_vacuum_scale_factor=0.005)"
    end
  end

  def down
    # revert to PG defaults
    execute "ALTER TABLE events set (autovacuum_vacuum_scale_factor=0.1)"
  end
end
