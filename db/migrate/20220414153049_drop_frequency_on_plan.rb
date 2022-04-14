class DropFrequencyOnPlan < ActiveRecord::Migration[7.0]
  def change
    remove_column :plans, :frequency
  end
end
