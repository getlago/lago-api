# frozen_string_literal: true

class AddUsageDiffToDailyUsages < ActiveRecord::Migration[7.1]
  def change
    add_column :daily_usages, :usage_diff, :jsonb, default: "{}", null: false
  end
end
