# frozen_string_literal: true

class AddMembershipStatusAndRevokedAt < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :memberships, bulk: true do |t|
        t.integer :status, null: false, default: 0
        t.datetime :revoked_at, null: true
      end
    end
  end
end
