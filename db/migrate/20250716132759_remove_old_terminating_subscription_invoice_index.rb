class RemoveOldTerminatingSubscriptionInvoiceIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    remove_index :invoice_subscriptions,
                 name: :index_unique_terminating_subscription_invoice,
                 algorithm: :concurrently
  end
end