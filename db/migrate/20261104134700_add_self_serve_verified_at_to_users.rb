# frozen_string_literal: true

class AddSelfServeVerifiedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    # Set when a self-serve signup creates the user: the email was confirmed, or a Workspace Google account signed up.
    add_column :users, :self_serve_verified_at, :datetime, if_not_exists: true
  end
end
