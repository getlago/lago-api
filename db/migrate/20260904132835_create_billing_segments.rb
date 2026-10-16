# frozen_string_literal: true

class CreateBillingSegments < ActiveRecord::Migration[8.0]
  def up
    enable_extension "btree_gist"

    create_enum :billing_segment_status, %w[pending processing done failed]

    create_table :billing_segments, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :contract, null: false, foreign_key: true, type: :uuid
      t.references :customer, null: false, foreign_key: true, type: :uuid
      t.references :contract_rate_card, null: false, foreign_key: true, type: :uuid

      t.references :invoice, foreign_key: true, type: :uuid
      t.references :rate_card_rate, foreign_key: true, type: :uuid
      t.references :rate_override, foreign_key: true, type: :uuid
      t.references :pricing_unit, foreign_key: true, type: :uuid
      t.jsonb :rate_properties, null: false, default: {}
      t.string :currency, null: false

      t.datetime :billing_at, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.datetime :cycle_started_at, null: false

      t.decimal :proration_ratio, precision: 30, scale: 10, null: false, default: 1
      t.enum :status, enum_type: :billing_segment_status, null: false, default: "pending"

      t.timestamps

      t.check_constraint "started_at <= ended_at", name: "billing_segments_period_bounds"
      t.check_constraint "cycle_started_at <= started_at", name: "billing_segments_cycle_bounds"
      t.check_constraint "proration_ratio >= 0 AND proration_ratio <= 1", name: "billing_segments_proration_ratio_bounds"
      t.check_constraint "rate_card_rate_id IS NOT NULL OR rate_override_id IS NOT NULL", name: "billing_segments_rate_presence"

      t.index [:contract_rate_card_id, :started_at], unique: true, name: "index_billing_segments_on_card_and_period"
      t.index [:contract_id, :billing_at, :status]
      t.index [:contract_rate_card_id, :cycle_started_at], name: "index_billing_segments_on_card_and_cycle"
    end

    safety_assured do
      execute <<~SQL
        ALTER TABLE billing_segments
        ADD CONSTRAINT billing_segments_no_overlapping_periods
        EXCLUDE USING gist (
          organization_id WITH =,
          contract_id WITH =,
          customer_id WITH =,
          contract_rate_card_id WITH =,
          tsrange(started_at, ended_at, '[]') WITH &&
        )
      SQL
    end
  end

  def down
    drop_table :billing_segments # rubocop:disable Lago/NoDropColumnOrTable
    drop_enum :billing_segment_status
  end
end
