# frozen_string_literal: true

class CreateInvoiceProgressiveBillingTriggerEnum < ActiveRecord::Migration[8.0]
  def change
    create_enum :invoice_progressive_billing_trigger, %w[usage_threshold wallet_expiration]
  end
end
