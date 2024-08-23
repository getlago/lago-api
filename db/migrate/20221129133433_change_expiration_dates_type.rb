# frozen_string_literal: true

class ChangeExpirationDatesType < ActiveRecord::Migration[7.0]
  def up
    add_column :coupons, :expiration_at, :datetime
    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE coupons SET expiration_at = (date_trunc('day', expiration_date) + interval '1 day' - interval '1 second')::timestamp
          WHERE expiration_date IS NOT NULL;
          SQL
        end
      end

      remove_column :coupons, :expiration_date
    end
  end

  def down
    add_column :coupons, :expiration_date, :date

    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE coupons SET expiration_date = DATE(expiration_at)
          WHERE expiration_at IS NOT NULL;
        SQL
      end
    end

    remove_column :coupons, :expiration_at
  end
end
