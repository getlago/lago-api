# frozen_string_literal: true

class RenameWalletsExpirationDate < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_column :wallets, :expiration_date, :expiration_at

      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE wallets SET expiration_at = (date_trunc('day', expiration_at) + interval '1 day' - interval '1 second')::timestamp;
          SQL
        end
      end
    end
  end
end
