class ChangeInvoiceDatesNilConstraints < ActiveRecord::Migration[7.0]
  def change
    change_column_null :invoices, :from_date, true
    change_column_null :invoices, :to_date, true
  end
end
