# frozen_string_literal: true

class AlterEventsVacuumSettings < ActiveRecord::Migration[7.1]
  def up
    execute "ALTER TABLE events set (autovacuum_vacuum_scale_factor=0.005)"
  end

  def down
    # revert to PG defaults
    execute "ALTER TABLE events set (autovacuum_vacuum_scale_factor=0.1)"
  end
end
