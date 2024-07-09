# frozen_string_literal: true

class RemoveNullConstraintOnAppliedTaxes < ActiveRecord::Migration[7.1]
  def change
    change_column_null :fees_taxes, :tax_id, true
    change_column_null :invoices_taxes, :tax_id, true
  end
end
