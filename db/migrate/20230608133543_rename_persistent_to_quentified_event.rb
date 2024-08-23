# frozen_string_literal: true

class RenamePersistentToQuentifiedEvent < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_table :persisted_events, :quantified_events
      rename_index :quantified_events, :index_search_persisted_events, :index_search_quantified_events
    end
  end
end
