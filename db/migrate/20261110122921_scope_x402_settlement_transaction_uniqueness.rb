# frozen_string_literal: true

class ScopeX402SettlementTransactionUniqueness < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_unique_index %i[organization_id network transaction_hash], name: :index_x402_settlements_on_organization_network_and_hash, where: "transaction_hash IS NOT NULL"
    add_unique_index %i[network transaction_hash], name: :index_x402_settlements_on_lago_network_and_hash, where: "transaction_hash IS NOT NULL AND settled_by = 'lago'"

    remove_index :x402_settlements, name: :index_x402_settlements_on_network_and_transaction_hash, algorithm: :concurrently, if_exists: true
  end

  def down
    add_unique_index %i[network transaction_hash], name: :index_x402_settlements_on_network_and_transaction_hash, where: "transaction_hash IS NOT NULL"

    remove_index :x402_settlements, name: :index_x402_settlements_on_organization_network_and_hash, algorithm: :concurrently, if_exists: true
    remove_index :x402_settlements, name: :index_x402_settlements_on_lago_network_and_hash, algorithm: :concurrently, if_exists: true
  end

  private

  def add_unique_index(columns, name:, where:)
    if index_exists?(:x402_settlements, nil, name:, valid: false)
      remove_index :x402_settlements, name:, algorithm: :concurrently
    end

    add_index :x402_settlements, columns, unique: true, where:, name:, algorithm: :concurrently, if_not_exists: true
  end
end
