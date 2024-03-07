# frozen_string_literal: true

class UpdateLastHourEventsMvToVersion3 < ActiveRecord::Migration[7.0]
  def change
    drop_view :last_hour_events_mv, materialized: true
    create_view :last_hour_events_mv, materialized: true, version: 3
  end
end
