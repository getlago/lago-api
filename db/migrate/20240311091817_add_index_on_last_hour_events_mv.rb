# frozen_string_literal: true

class AddIndexOnLastHourEventsMv < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    safety_assured do
      add_index :last_hour_events_mv, :organization_id, if_not_exists: true
    end
  end
end
