# frozen_string_literal: true

class AddPropertiesToPersistedEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :persisted_events, :properties, :jsonb, null: false, default: {}
  end
end
