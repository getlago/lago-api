# frozen_string_literal: true

class UpdateLastHourEventsMvV04 < ActiveRecord::Migration[7.1]
  def change
    drop_view :last_hour_events_mv, materialized: true
    create_view :last_hour_events_mv, materialized: true, version: 4
  end
end
