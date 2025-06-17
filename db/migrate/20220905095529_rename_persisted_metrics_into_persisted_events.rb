# frozen_string_literal: true

class RenamePersistedMetricsIntoPersistedEvents < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_table :persisted_metrics, :persisted_events
      rename_index :persisted_events, :index_search_persisted_metrics, :index_search_persisted_events
    end
  end
end
