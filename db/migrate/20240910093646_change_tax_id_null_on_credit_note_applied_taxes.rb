class ChangeTaxIdNullOnCreditNoteAppliedTaxes < ActiveRecord::Migration[7.1]
  def change
    change_column_null :credit_notes_taxes, :tax_id, true
  end
end
