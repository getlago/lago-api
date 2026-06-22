# frozen_string_literal: true

class AddIndexOnSubscriptionsForPlanIdAndStatus < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :subscriptions,
      [:plan_id, :status],
      where: "status IN (0, 1)",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
