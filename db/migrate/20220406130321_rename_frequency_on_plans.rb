class RenameFrequencyOnPlans < ActiveRecord::Migration[7.0]
  def change
    rename_column :plans, :frequency, :interval
  end
end
