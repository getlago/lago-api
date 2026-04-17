# frozen_string_literal: true

class AddOriginalFeeIdToFees < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :fees, :original_fee, type: :uuid, index: {algorithm: :concurrently}
  end
end
