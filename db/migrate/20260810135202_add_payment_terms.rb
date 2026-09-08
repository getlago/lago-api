# frozen_string_literal: true

class AddPaymentTerms < ActiveRecord::Migration[8.0]
  def change
    add_column :customers, :payment_term, :jsonb
    add_column :billing_entities, :payment_term, :jsonb
    add_column :invoices, :payment_term, :jsonb
    add_column :invoices, :payment_term_source, :string
  end
end
