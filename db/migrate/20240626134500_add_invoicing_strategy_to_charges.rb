class AddInvoicingStrategyToCharges < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :charges, :invoicing_strategy, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        Charge.where(pay_in_advance: true, invoiceable: true).update_all(invoicing_strategy: 1) # rubocop:disable Rails/SkipsModelValidations
        Charge.where(pay_in_advance: true, invoiceable: false).update_all(invoicing_strategy: 3) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
