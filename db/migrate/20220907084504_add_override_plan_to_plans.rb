class AddOverridePlanToPlans < ActiveRecord::Migration[7.0]
  def change
    add_reference :plans, :overridden_plan, type: :uuid, null: true, index: true, foreign_key: { to_table: :plans }
  end
end
