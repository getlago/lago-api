class RenameVatOnFees < ActiveRecord::Migration[7.0]
  def change
    rename_column :fees, :vat_cents, :vat_amount_cents
    rename_column :fees, :vat_currency, :vat_amount_currency
  end
end
