class RemoveProRataFromPlans < ActiveRecord::Migration[7.0]
  def change
    remove_column :plans, :pro_rata
  end
end
