# frozen_string_literal: true

# A key with a membership is minted for the AI agent and carries that member's permissions.
class AddMembershipToApiKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :api_keys, :membership_id, :uuid, if_not_exists: true
    add_foreign_key :api_keys, :memberships, validate: false, if_not_exists: true
  end
end
