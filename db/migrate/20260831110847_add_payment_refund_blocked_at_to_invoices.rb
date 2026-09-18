# frozen_string_literal: true

class AddPaymentRefundBlockedAtToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :payment_refund_blocked_at, :datetime, if_not_exists: true
  end
end
