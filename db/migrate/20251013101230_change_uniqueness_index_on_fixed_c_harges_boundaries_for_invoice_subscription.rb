# frozen_string_literal: true

class ChangeUniquenessIndexOnFixedCHargesBoundariesForInvoiceSubscription < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  def up
    remove_index :invoice_subscriptions, name: :index_uniq_invoice_subscriptions_on_fixed_charges_boundaries
    remove_index :invoice_subscriptions, name: :index_uniq_invoice_subscriptions_on_charges_from_to_datetime
    
    add_index :invoice_subscriptions,
      [:subscription_id,
        :fixed_charges_from_datetime,
        :fixed_charges_to_datetime,
        :charges_from_datetime,
        :charges_to_datetime
      ],
      unique: true,
      name: :index_uniq_invoice_subscriptions_on_all_charges_boundaries,
      where: "created_at >= '2023-06-09 00:00:00' AND recurring IS TRUE AND regenerated_invoice_id IS NULL",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :invoice_subscriptions, name: :index_uniq_invoice_subscriptions_on_all_charges_boundaries
    add_index :invoice_subscriptions,
      [:subscription_id, :fixed_charges_from_datetime, :fixed_charges_to_datetime],
      unique: true,
      name: :index_uniq_invoice_subscriptions_on_fixed_charges_boundaries,
      where: "recurring IS TRUE AND regenerated_invoice_id IS NULL",
      algorithm: :concurrently,
      if_not_exists: true
    add_index :invoice_subscriptions,
      [:subscription_id, :charges_from_datetime, :charges_to_datetime],
      unique: true,
      name: :index_uniq_invoice_subscriptions_on_charges_from_to_datetime,
      where: "created_at >= '2023-06-09 00:00:00' AND recurring IS TRUE AND regenerated_invoice_id IS NULL",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
