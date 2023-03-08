# frozen_string_literal: true

class AddInstantEventIdToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :instant_event_id, :uuid
  end
end
