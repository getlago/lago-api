# frozen_string_literal: true

class ChangeInvoicesIndexOnBillingEntitySequentialId < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    # Change column default in a separate transaction to avoid locking
    change_column_default :invoices, :billing_entity_sequential_id, from: 0, to: nil

    Invoice.in_batches(of: 1000) do |batch|
      batch.update_all( # rubocop:disable Rails/SkipsModelValidations
        "billing_entity_sequential_id = CASE WHEN organization_sequential_id = 0 THEN NULL ELSE organization_sequential_id END"
      )
    end

    # Check if the index exists before trying to remove it
    # Include all options to match the exact index
    if index_exists?(:invoices, [:organization_id, :billing_entity_sequential_id],
                     order: {billing_entity_sequential_id: :desc},
                     include: %i[self_billed])
      remove_index :invoices, [:organization_id, :billing_entity_sequential_id],
        order: {billing_entity_sequential_id: :desc},
        algorithm: :concurrently,
        if_not_exists: true,
        include: %i[self_billed]
    end

    add_index :invoices, [:billing_entity_id, :billing_entity_sequential_id],
      order: {billing_entity_sequential_id: :desc},
      algorithm: :concurrently,
      if_not_exists: true,
      include: %i[self_billed],
      unique: true
  end

  def down
    if index_exists?(:invoices, [:billing_entity_id, :billing_entity_sequential_id],
                     order: {billing_entity_sequential_id: :desc},
                     include: %i[self_billed],
                     unique: true)
      remove_index :invoices, [:billing_entity_id, :billing_entity_sequential_id],
        order: {billing_entity_sequential_id: :desc},
        algorithm: :concurrently,
        if_not_exists: true,
        include: %i[self_billed],
        unique: true
    end

    add_index :invoices, [:organization_id, :billing_entity_sequential_id],
      order: {billing_entity_sequential_id: :desc},
      algorithm: :concurrently,
      if_not_exists: true,
      include: %i[self_billed]

    # Revert the column default
    change_column_default :invoices, :billing_entity_sequential_id, from: nil, to: 0
  end
end
