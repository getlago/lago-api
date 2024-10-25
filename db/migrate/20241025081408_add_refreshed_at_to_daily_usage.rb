# frozen_string_literal: true

class AddRefreshedAtToDailyUsage < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      add_column :daily_usages, :refreshed_at, :datetime, null: false
    end
  end
end
