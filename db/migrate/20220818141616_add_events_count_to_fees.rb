# frozen_string_literal: true

class AddEventsCountToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :events_count, :integer
  end
end
