# frozen_string_literal: true

class AddPaymentDisputedToInvoices < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :invoices, bulk: true do |t|
        t.datetime :payment_dispute_lost_at, default: nil
      end
    end
  end
end
