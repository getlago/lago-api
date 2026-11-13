# frozen_string_literal: true

# A key with a membership is minted for the AI agent and carries that member's permissions.
class AddMembershipToApiKeys < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :api_keys, :membership, type: :uuid, null: true, index: {algorithm: :concurrently}
    add_foreign_key :api_keys, :memberships, validate: false, if_not_exists: true
  end
end
