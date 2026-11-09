# frozen_string_literal: true

# The case-insensitive lookups of a user by email (the fallback of password and SSO logins, invites,
# password resets, signups) compare LOWER(email), which no index served: each scanned the users table.
class AddUsersLowerEmailIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:users, nil, name: :index_users_on_lower_email, valid: false)
      remove_index :users, name: :index_users_on_lower_email, algorithm: :concurrently
    end

    add_index :users, "LOWER(email)", name: :index_users_on_lower_email, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :users, name: :index_users_on_lower_email, algorithm: :concurrently, if_exists: true
  end
end
