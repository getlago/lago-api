# frozen_string_literal: true

class AddTimezoneToDailyUsages < ActiveRecord::Migration[7.1]
  def change
    add_column :daily_usages, :timezone, :string, null: false, default: 'UTC'
  end
end
