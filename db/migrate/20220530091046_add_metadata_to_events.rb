# frozen_string_literal: true

class AddMetadataToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :metadata, :jsonb, null: false, default: {}
  end
end
