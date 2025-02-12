# frozen_string_literal: true

class AddReferencesToBillingEntities < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_reference :billing_entities, :organization, index: {algorithm: :concurrently}, type: :uuid
    add_reference :billing_entities, :applied_dunning_campaign, index: {algorithm: :concurrently}, type: :uuid

    add_reference :customers, :billing_entity, index: {algorithm: :concurrently}, type: :uuid
    add_reference :invoices, :billing_entity, index: {algorithm: :concurrently}, type: :uuid
    # add_reference :daily_usages, :billing_entity, index: {algorithm: :concurrently}, type: :uuid
    # add_reference :integrations, :billing_entity, index: {algorithm: :concurrently}, type: :uuid
    # add_reference :payment_providers, :billing_entity, index: {algorithm: :concurrently}, type: :uuid
    # add_reference :payment_requests, :billing_entity, index: {algorithm: :concurrently}, type: :uuid
    # add_reference :cached_aggregations, :billing_entity, index: {algorithm: :concurrently}, type: :uuid
    # add_reference :data_exports, :billing_entity, index: {algorithm: :concurrently}, type: :uuid
    add_reference :invoice_custom_section_selections, :billing_entity, index: {algorithm: :concurrently}, type: :uuid
    add_reference :error_details, :billing_entity, index: {algorithm: :concurrently}, type: :uuid
    add_reference :fees, :billing_entity, index: {algorithm: :concurrently}, type: :uuid

    add_column :organizations, :max_billing_entities, :integer, default: 1
  end
end
