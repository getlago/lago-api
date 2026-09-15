# frozen_string_literal: true

class RelaxNetPaymentTermNullability < ActiveRecord::Migration[8.0]
  def change
    change_column_null :billing_entities, :net_payment_term, true
    change_column_null :invoices, :net_payment_term, true
  end
end
