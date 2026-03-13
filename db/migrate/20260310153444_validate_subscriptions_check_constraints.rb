# frozen_string_literal: true

class ValidateSubscriptionsCheckConstraints < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      validate_check_constraint :subscriptions, name: "free_until_should_be_after_start"
      validate_check_constraint :subscriptions, name: "free_until_should_be_before_end"
    end
  end

  def down
  end
end
