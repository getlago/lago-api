# frozen_string_literal: true

class MakeFixedChargesBoundariesIndexUnique < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Remove the existing non-unique index
    remove_index :invoice_subscriptions,
      name: :index_invoice_subscriptions_on_fixed_charges_boundaries,
      if_exists: true

    # Add unique index (only for non-NULL fixed_charges boundaries)
    add_index :invoice_subscriptions,
      [:subscription_id, :fixed_charges_from_datetime, :fixed_charges_to_datetime],
      unique: true,
      where: "fixed_charges_from_datetime IS NOT NULL AND recurring = TRUE AND regenerated_invoice_id IS NULL",
      name: :index_uniq_invoice_subscriptions_on_fixed_charges_boundaries,
      algorithm: :concurrently
  end

  def down
    remove_index :invoice_subscriptions,
      name: :index_uniq_invoice_subscriptions_on_fixed_charges_boundaries,
      if_exists: true

    add_index :invoice_subscriptions,
      [:subscription_id, :fixed_charges_from_datetime, :fixed_charges_to_datetime],
      where: "recurring IS TRUE AND regenerated_invoice_id IS NULL",
      name: :index_invoice_subscriptions_on_fixed_charges_boundaries,
      algorithm: :concurrently
  end
end
