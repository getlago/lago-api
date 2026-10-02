# frozen_string_literal: true

class AddX402ForeignKeys < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  FOREIGN_KEYS = [
    %i[x402_connections organizations],
    %i[x402_settlements organizations],
    %i[x402_settlements customers],
    %i[x402_settlements subscriptions],
    %i[x402_settlements wallet_transactions],
    %i[x402_settlements payments],
    %i[x402_settlements invoices]
  ].freeze

  def up
    previous_lock_timeout = select_value("SHOW lock_timeout")
    safety_assured { execute("SET lock_timeout = '5s'") }

    FOREIGN_KEYS.each do |from_table, to_table|
      add_foreign_key from_table, to_table, validate: false, if_not_exists: true
    end
  ensure
    if previous_lock_timeout
      safety_assured { execute("SET lock_timeout = #{connection.quote(previous_lock_timeout)}") }
    end
  end

  def down
    FOREIGN_KEYS.reverse_each do |from_table, to_table|
      remove_foreign_key from_table, to_table, if_exists: true
    end
  end
end
