# frozen_string_literal: true

class AddX402AgentAddressIndexToCustomers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    if index_exists?(:customers, nil, name: :index_customers_on_organization_id_and_x402_agent_address, valid: false)
      remove_index :customers, name: :index_customers_on_organization_id_and_x402_agent_address, algorithm: :concurrently
    end

    add_index :customers,
      %i[organization_id x402_agent_address],
      unique: true,
      where: "deleted_at IS NULL AND x402_agent_address IS NOT NULL",
      name: :index_customers_on_organization_id_and_x402_agent_address,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :customers, name: :index_customers_on_organization_id_and_x402_agent_address, algorithm: :concurrently, if_exists: true
  end
end
