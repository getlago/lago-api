# frozen_string_literal: true

class AddCodeToContracts < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :contracts, :code, :string, if_not_exists: true

    reversible do |dir|
      dir.up do
        Contract.unscoped.where(code: nil).in_batches do |contracts|
          contracts.update_all("code = id::text, updated_at = CURRENT_TIMESTAMP") # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end
  end
end
