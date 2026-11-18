# frozen_string_literal: true

class SetContractCodeNotNull < ActiveRecord::Migration[8.1]
  def up
    validate_check_constraint :contracts, name: "contracts_code_not_null"
    change_column_null :contracts, :code, false
    remove_check_constraint :contracts, name: "contracts_code_not_null"
  end

  def down
    add_check_constraint :contracts, "code IS NOT NULL",
      name: "contracts_code_not_null", validate: false, if_not_exists: true
    change_column_null :contracts, :code, true
  end
end
