# frozen_string_literal: true

class ValidateSubscriptionsBillingEntitiesForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :subscriptions, :billing_entities
  end
end
