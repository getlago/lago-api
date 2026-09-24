# frozen_string_literal: true

class AddX402AgentAddressToCustomers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # Non-transactional DDL can stop halfway, so both statements are idempotent (precedent: 20260908154307).
  def up
    add_column :customers, :x402_agent_address, :string, if_not_exists: true
    add_index :customers, %i[organization_id x402_agent_address],
      unique: true,
      where: "deleted_at IS NULL AND x402_agent_address IS NOT NULL",
      algorithm: :concurrently,
      name: "index_customers_on_organization_id_and_x402_agent_address",
      if_not_exists: true
  end

  def down
    remove_index :customers, name: "index_customers_on_organization_id_and_x402_agent_address", algorithm: :concurrently, if_exists: true
    remove_column :customers, :x402_agent_address, if_exists: true # rubocop:disable Lago/NoDropColumnOrTable
  end
end
