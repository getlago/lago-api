# frozen_string_literal: true

class CreateAdminUsers < ActiveRecord::Migration[8.0]
  def change
    create_enum :admin_user_role, %w[admin cs]

    create_table :admin_users, id: :uuid do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.enum :role, enum_type: :admin_user_role, null: false, default: "cs"
      t.datetime :last_sign_in_at

      t.timestamps
    end

    add_index :admin_users, "LOWER(email)", unique: true, name: "index_admin_users_on_lower_email"
  end
end
