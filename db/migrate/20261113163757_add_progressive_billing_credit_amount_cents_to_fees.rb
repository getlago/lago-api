# frozen_string_literal: true

class AddProgressiveBillingCreditAmountCentsToFees < ActiveRecord::Migration[8.1]
  def change
    add_column :fees, :progressive_billing_credit_amount_cents, :bigint, null: false, default: 0, if_not_exists: true
  end
end
