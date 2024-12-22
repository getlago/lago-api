# frozen_string_literal: true

class AddIndexOnUsageDateToDailyUsages < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    safety_assured do
      add_index :daily_usages, :usage_date, algorithm: :concurrently
    end
  end
end
