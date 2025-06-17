# frozen_string_literal: true

class AddOrganizationIdToFees < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_reference :fees, :organization, type: :uuid, index: {algorithm: :concurrently}
  end
end
