# frozen_string_literal: true

class AddPolymorphicRefundableToRefunds < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :refunds, :refundable, type: :uuid, polymorphic: true, index: {algorithm: :concurrently}

    safety_assured do
      change_column_null :refunds, :credit_note_id, true
    end

    add_column :refunds, :reason, :string
  end
end
