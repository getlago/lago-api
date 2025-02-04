# frozen_string_literal: true

class CreateHoldings < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    create_table :holdings, id: :uuid do |t|
      t.string :name, null: false
      t.string :api_key
      t.string :hmac_key
      t.string :premium_integrations, array: true, default: [], null: false

      t.timestamps
    end

    add_reference :organizations, :holding, type: :uuid, index: {algorithm: :concurrently}
    add_reference :billable_metrics, :holding, type: :uuid, index: {algorithm: :concurrently}
    add_reference :plans, :holding, type: :uuid, index: {algorithm: :concurrently}
    add_reference :dunning_campaigns, :holding, type: :uuid, index: {algorithm: :concurrently}
    add_reference :taxes, :holding, type: :uuid, index: {algorithm: :concurrently}
    add_reference :memberships, :holding, type: :uuid, index: {algorithm: :concurrently}
    add_reference :coupons, :holding, type: :uuid, index: {algorithm: :concurrently}
    add_reference :add_ons, :holding, type: :uuid, index: {algorithm: :concurrently}
    add_reference :invites, :holding, type: :uuid, index: {algorithm: :concurrently}
    add_reference :invoice_custom_sections, :holding, type: :uuid, index: {algorithm: :concurrently}
  end
end
