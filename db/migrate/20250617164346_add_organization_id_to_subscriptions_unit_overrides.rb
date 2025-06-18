# frozen_string_literal: true

class AddOrganizationIdToSubscriptionsUnitOverrides < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_reference :subscriptions_units_overrides, :organization, type: :uuid, index: {algorithm: :concurrently}
  end
end
