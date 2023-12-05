# frozen_string_literal: true

class RemoveEventsQuantifiedEventsRelation < ActiveRecord::Migration[7.0]
  def up
    remove_column :events, :quantified_event_id
  end

  def down
    add_column :events, :quantified_event_id, :uuid
    add_index :events, :quantified_event_id
  end
end
