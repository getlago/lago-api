# frozen_string_literal: true

class ValidateCouponsCodeNotNull < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_check_constraint :coupons, name: "coupons_code_not_null"
    change_column_null :coupons, :code, false
    remove_check_constraint :coupons, name: "coupons_code_not_null"
  end
end
