# frozen_string_literal: true

# One QuickBooks company per organization: the model validation alone lets two concurrent creates
# both pass, and the Nango lookup between the check and the insert makes that window seconds long.
class AddQuickbooksRealmIdIndexToIntegrations < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = :index_integrations_on_organization_id_and_quickbooks_realm_id

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:integrations, name: INDEX_NAME, valid: false)
      remove_index :integrations, name: INDEX_NAME, algorithm: :concurrently
    end

    add_index :integrations,
      "organization_id, (settings->>'realm_id')",
      name: INDEX_NAME,
      unique: true,
      where: "type = 'Integrations::QuickbooksIntegration' AND (settings->>'realm_id') IS NOT NULL",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :integrations, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end
