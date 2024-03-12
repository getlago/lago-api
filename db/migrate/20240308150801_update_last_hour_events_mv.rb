# frozen_string_literal: true

class UpdateLastHourEventsMv < ActiveRecord::Migration[7.0]
  def change
    drop_view :last_hour_events_mv, materialized: true
    create_view :last_hour_events_mv, materialized: { no_data: true }, version: 3
    add_index :last_hour_events_mv, :organization_id
  end
end
