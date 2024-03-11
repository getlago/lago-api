# frozen_string_literal: true

class AddIndexOnLastHourEventsMv < ActiveRecord::Migration[7.0]
  def change
    add_index :last_hour_events_mv, :organization_id
  end
end
