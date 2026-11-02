# frozen_string_literal: true

class IndexContractDailyUsages < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # The subscription indexes, for contract rows only: partial, so that they skip the
  # subscription rows the table is made of.
  INDEXES = {
    index_daily_usages_on_contract_id_and_usage_date: [:contract_id, :usage_date],
    index_daily_usages_on_contract_rate_card_id_and_usage_date: [:contract_rate_card_id, :usage_date],
    index_daily_usages_on_organization_id_and_external_contract_id: [:organization_id, :external_contract_id]
  }.freeze

  def up
    INDEXES.each do |name, columns|
      if index_exists?(:daily_usages, nil, name:, valid: false)
        remove_index :daily_usages, name:, algorithm: :concurrently
      end

      add_index :daily_usages,
        columns,
        where: "contract_id IS NOT NULL",
        name:,
        algorithm: :concurrently,
        if_not_exists: true
    end
  end

  def down
    INDEXES.each_key do |name|
      remove_index :daily_usages, name:, algorithm: :concurrently, if_exists: true
    end
  end
end
