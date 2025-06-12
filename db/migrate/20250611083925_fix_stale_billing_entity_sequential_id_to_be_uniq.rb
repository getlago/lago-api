# frozen_string_literal: true

class FixStaleBillingEntitySequentialIdToBeUniq < ActiveRecord::Migration[8.0]
  class Invoice < ApplicationRecord
  end

  class BillingEntity < ApplicationRecord
  end

  def up
    # BillingEntities::ChangeInvoiceNumberingService -- if we switch from per_customer 
    # to per_billing_entity, we'll recalculate the billing_entity_sequential_id
    BillingEntity.where(document_numbering: 'per_customer').find_each do |billing_entity|
      # do we want to update all or only duplicated?
      duplicates = Invoice.where(billing_entity_id: billing_entity.id)
        .non_self_billed.with_generated_number
        .where.not(billing_entity_sequential_id: nil)
        .group(:billing_entity_sequential_id)
        .having('COUNT(*) > 1')
        .pluck(:billing_entity_sequential_id)
      next if duplicates.empty?

      Invoice.where(billing_entity_id: billing_entity.id)
        .non_self_billed.with_generated_number
        .where.not(billing_entity_sequential_id: nil)
        .where(billing_entity_sequential_id: duplicates)
        .update_all("billing_entity_sequential_id = NULL")
    end

    BillingEntity.where(document_numbering: 'per_billing_entity').find_each do |billing_entity|
      # group invoices by billing_entity_sequential_id and find groups with more than 1 invoice
      duplicates = Invoice.where(billing_entity_id: billing_entity.id)
        .non_self_billed.with_generated_number
        .where.not(billing_entity_sequential_id: nil)
        .group(:billing_entity_sequential_id)
        .having('COUNT(*) > 1')
        .pluck(:billing_entity_sequential_id)
      next if duplicates.empty?

      invoices_count = Invoice.where(billing_entity_id: billing_entity.id, billing_entity_sequential_id: duplicates).count
      latest_invoice = Invoice.where(billing_entity_id: billing_entity.id, billing_entity_sequential_id: duplicates).order(:created_at).last
      puts "Found #{duplicates.count} duplicates for billing_entity: #{billing_entity.name}; Affected invoices: #{invoices_count}; Latest invoice: (#{latest_invoice.created_at})"

      # find the highest billing_entity_sequential_id for the billing_entity
      existing_max_number = Invoice.where(billing_entity_id: billing_entity.id)
        .non_self_billed.with_generated_number
        .where.not(billing_entity_sequential_id: nil)
        .maximum(:billing_entity_sequential_id)

      if duplicates.max >= existing_max_number
        puts "-" * 80
        puts "billing_entity: #{billing_entity.name}"
        puts "WARNING: DUPLICATED LATEST BILLING_ENTITY_SEQUENTIAL_ID: #{duplicates.max} >= #{existing_max_number}"
        next
      end

      # for each duplicate, set the billing_entity_sequential_id to NULL
      Invoice.where(billing_entity_id: billing_entity.id, billing_entity_sequential_id: duplicates)
        .update_all("billing_entity_sequential_id = NULL")
    end
  end

  def down
    # No down migration needed
  end
end
