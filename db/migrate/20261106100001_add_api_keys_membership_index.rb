# frozen_string_literal: true

class AddApiKeysMembershipIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:api_keys, nil, name: :index_api_keys_on_membership_id, valid: false)
      remove_index :api_keys, name: :index_api_keys_on_membership_id, algorithm: :concurrently
    end

    add_index :api_keys, :membership_id, name: :index_api_keys_on_membership_id, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :api_keys, name: :index_api_keys_on_membership_id, algorithm: :concurrently, if_exists: true
  end
end
