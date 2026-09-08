# frozen_string_literal: true

class ValidateSubscriptionsPaymentMethodsForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :subscriptions, :payment_methods
  end
end
