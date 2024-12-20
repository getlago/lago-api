# frozen_string_literal: true

class AddUsageDateToDailyUsages < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      add_column :daily_usages, :usage_date, :date
    end
  end
end
