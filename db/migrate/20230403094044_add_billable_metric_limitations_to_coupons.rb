# frozen_string_literal: true

class AddBillableMetricLimitationsToCoupons < ActiveRecord::Migration[7.0]
  def change
    add_column :coupons, :limited_billable_metrics, :boolean, default: false, null: false

    change_column_null :coupon_plans, :plan_id, true

    add_reference :coupon_plans, :billable_metric, type: :uuid, null: true, index: true, foreign_key: true

    rename_table("coupon_plans", "coupon_targets")
  end
end
