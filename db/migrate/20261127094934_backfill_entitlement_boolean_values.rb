# frozen_string_literal: true

class BackfillEntitlementBooleanValues < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  class EntitlementValue < ApplicationRecord
    self.table_name = "entitlement_entitlement_values"
  end

  class Privilege < ApplicationRecord
    self.table_name = "entitlement_privileges"
  end

  # Booleans used to be stored as "t" or "f", the cast of a JSON boolean into the string column.
  def up
    boolean_privileges = Privilege.where(value_type: "boolean").select(:id)

    {"t" => "true", "f" => "false"}.each do |stored, word|
      EntitlementValue.where(entitlement_privilege_id: boolean_privileges, value: stored).in_batches do |batch|
        batch.update_all(value: word, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end

  def down
  end
end
