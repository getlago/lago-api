# frozen_string_literal: true

class BackfillAndConstrainContractCodes < ActiveRecord::Migration[8.1]
  # Run only after all application instances require contract codes.
  disable_ddl_transaction!

  def up
    Contract.unscoped.where(code: nil).in_batches do |contracts|
      contracts.update_all("code = id::text, updated_at = CURRENT_TIMESTAMP") # rubocop:disable Rails/SkipsModelValidations
    end

    add_check_constraint :contracts, "code IS NOT NULL",
      name: "contracts_code_not_null", validate: false, if_not_exists: true
  end

  def down
    remove_check_constraint :contracts, name: "contracts_code_not_null", if_exists: true
  end
end
