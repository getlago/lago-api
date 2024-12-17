# frozen_string_literal: true

class AddTaxStatusToInvoices < ActiveRecord::Migration[7.1]
  def change
    create_enum :tax_status, %w[pending succeeded failed]

    safety_assured do
      change_table :invoices do |t|
        t.enum :tax_status, enum_type: 'tax_status', null: true
      end
    end
  end
end
