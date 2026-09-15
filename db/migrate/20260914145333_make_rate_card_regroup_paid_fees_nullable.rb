# frozen_string_literal: true

class MakeRateCardRegroupPaidFeesNullable < ActiveRecord::Migration[8.0]
  def up
    change_column_default :rate_cards, :regroup_paid_fees, nil
    change_column_null :rate_cards, :regroup_paid_fees, true

    # `none` is retired: a fee left standalone is now represented by NULL,
    # matching the legacy charge `regroup_paid_fees` contract. The enum type
    # keeps the (now unused) `none` value — Postgres cannot drop it in place.
    safety_assured { execute("UPDATE rate_cards SET regroup_paid_fees = NULL WHERE regroup_paid_fees = 'none'") }
  end

  def down
    safety_assured { execute("UPDATE rate_cards SET regroup_paid_fees = 'none' WHERE regroup_paid_fees IS NULL") }

    change_column_null :rate_cards, :regroup_paid_fees, false
    change_column_default :rate_cards, :regroup_paid_fees, "none"
  end
end
