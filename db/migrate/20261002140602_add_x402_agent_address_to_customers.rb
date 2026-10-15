# frozen_string_literal: true

class AddX402AgentAddressToCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :customers, :x402_agent_address, :string, if_not_exists: true
  end
end
