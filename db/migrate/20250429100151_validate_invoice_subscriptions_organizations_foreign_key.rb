# frozen_string_literal: true

class ValidateInvoiceSubscriptionsOrganizationsForeignKey < ActiveRecord::Migration[7.2]
  def change
    validate_foreign_key :invoice_subscriptions, :organizations
  end
end
