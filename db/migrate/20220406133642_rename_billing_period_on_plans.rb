class RenameBillingPeriodOnPlans < ActiveRecord::Migration[7.0]
  def change
    rename_column :plans, :billing_period, :frequency
  end
end
