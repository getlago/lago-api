# frozen_string_literal: true

class ChangeSubscriptionDateType < ActiveRecord::Migration[7.0]
  def up
    add_column :subscriptions, :subscription_at, :datetime
    safety_assured do
      execute <<-SQL
      UPDATE subscriptions
      SET subscription_at = subscription_date::timestamp
      WHERE subscription_date IS NOT NULL;
      SQL

      remove_column :subscriptions, :subscription_date
    end
  end

  def down
    add_column :subscriptions, :subscription_date, :date

    execute <<-SQL
      UPDATE subscriptions
      SET subscription_date = DATE(subscription_at)
      WHERE subscription_at IS NOT NULL;
      WHERE
    SQL

    remove_column :subscriptions, :subscription_at
  end
end
