# frozen_string_literal: true

class CreateLastHourEventsMv < ActiveRecord::Migration[7.0]
  def change
    create_view :last_hour_events_mv, materialized: true
  end
end
