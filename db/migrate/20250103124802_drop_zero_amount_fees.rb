# frozen_string_literal: true

class DropZeroAmountFees < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  class FeesTax < ApplicationRecord; end

  class Fee < ApplicationRecord; end

  def change
    sql = <<~SQL
      SELECT fees.id FROM fees
      INNER JOIN invoices ON fees.invoice_id = invoices.id
      INNER JOIN organizations ON invoices.organization_id = organizations.id
      WHERE
        invoices.status IN (1, 2, 6) -- finalized, voided and closed
        AND fees.fee_type = 0 -- charge
        AND fees.amount_cents = 0
        AND fees.units = 0
        AND fees.pay_in_advance = false
        AND fees.true_up_parent_fee_id IS NULL
        AND fees.id NOT IN (
          SELECT f.true_up_parent_fee_id
          FROM fees f
          WHERE f.true_up_parent_fee_id IS NOT NULL
        )
        AND fees.id NOT IN (
          SELECT fee_id
          FROM adjusted_fees
          WHERE adjusted_fees.fee_id IS NOT NULL
        )
        AND NOT ('zero_amount_fees' = ANY(organizations.premium_integrations))
        LIMIT 1000
    SQL

    while (ids = ActiveRecord::Base.connection.select_all(sql).rows.map(&:first)).any?
      FeesTax.where(fee_id: ids).delete_all
      Fee.where(id: ids).delete_all

      puts "Deleted #{ids.size} fees - #{Time.current.iso8601}" # rubocop:disable Rails/Output
    end
  end
end
