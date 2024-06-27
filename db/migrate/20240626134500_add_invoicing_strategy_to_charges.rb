class AddInvoicingStrategyToCharges < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :charges, :invoicing_strategy, :integer, default: nil

    reversible do |dir|
      dir.up do
        Charge.where(pay_in_advance: true, invoiceable: true).update_all(invoicing_strategy: :in_advance) # rubocop:disable Rails/SkipsModelValidations
        Charge.where(pay_in_advance: true, invoiceable: false).update_all(invoicing_strategy: :never) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
