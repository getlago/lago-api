# frozen_string_literal: true

class AddEmailHashToAgentClaims < ActiveRecord::Migration[8.1]
  def change
    # A digest of the owner's mailbox, written when the claim starts: the free credits are granted once per mailbox.
    add_column :agent_claims, :email_hash, :string, if_not_exists: true
  end
end
