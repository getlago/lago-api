# frozen_string_literal: true

# The exact-match lookups of a user by email, which every sign-in path runs before its LOWER(email)
# fallback, had no index either: each scanned the users table.
class AddUsersEmailIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:users, :email, name: :index_users_on_email, valid: false)
      remove_index :users, name: :index_users_on_email, algorithm: :concurrently
    end

    add_index :users, :email, name: :index_users_on_email, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :users, name: :index_users_on_email, algorithm: :concurrently, if_exists: true
  end
end
