# frozen_string_literal: true

class RenameUsageTresholds < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      rename_table :usage_tresholds, :usage_thresholds
      rename_column :usage_thresholds, :treshold_display_name, :threshold_display_name
    end
  end
end
