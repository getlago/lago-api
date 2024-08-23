# frozen_string_literal: true

class AddUniqueIndexOnMemberships < ActiveRecord::Migration[7.0]
  def change
    LagoApi::Application.load_tasks
    Rake::Task['memberships:revoke_duplicates'].invoke

    safety_assured do
      add_index :memberships, [:user_id, :organization_id], unique: true, where: 'revoked_at IS NULL'
    end
  end
end
