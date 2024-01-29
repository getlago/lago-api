# frozen_string_literal: true

class AddGroupedByToQuantifiedEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :quantified_events, :grouped_by, :jsonb, null: false, default: {}
  end
end
