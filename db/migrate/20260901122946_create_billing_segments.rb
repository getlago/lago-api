# frozen_string_literal: true

class CreateBillingSegments < ActiveRecord::Migration[8.0]
  def change
    enable_extension "btree_gist"

    create_enum :billing_segment_status, %w[pending processing done failed]

    create_table :billing_segments, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subscription, null: false, foreign_key: true, type: :uuid
      # Denormalized so the clock scan and the per-customer grouping stay index-only.
      t.references :customer, null: false, foreign_key: true, type: :uuid
      t.references :subscription_rate_card, null: false, foreign_key: true, type: :uuid

      # The invoice this segment was billed into (nil until processed). Records the
      # outbox result and lets us re-enqueue it (status -> pending, invoice_id -> nil)
      # when that invoice is voided, deleted or retried.
      t.references :invoice, foreign_key: true, type: :uuid

      # The pricing in force when the segment was scheduled, snapshotted so a later
      # catalog change cannot re-price what has already been billed.
      t.references :rate_card_rate, foreign_key: true, type: :uuid
      t.references :rate_override, foreign_key: true, type: :uuid
      t.references :pricing_unit, foreign_key: true, type: :uuid
      t.jsonb :rate_properties, null: false, default: {}

      # The instant this segment becomes billable — the boundary the scheduler picked it
      # up on. Segments sharing a subscription and a billing_at are invoiced together.
      t.datetime :billing_at, null: false

      # The window this segment is billed for. Half-open in the engine, stored inclusive:
      # ended_at is the last instant covered, a microsecond before the window closes.
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false

      # Where the cycle this segment belongs to opened. A cycle billed whole has one segment
      # and cycle_started_at equals started_at; one cut by a rate change has several sharing it.
      #
      # Stored rather than derived because the cycle is the unit several things are measured
      # against — the unused-advance credit, an advance increase, the invoice line that shows
      # a period billed in parts — and none of them can recover it from a row: consecutive
      # segments are contiguous, so a rate cut and a cycle boundary look identical. Deriving
      # it means rebuilding the whole schedule, and even that is only right while the phase
      # configuration has not changed since. The window is a fact about what was billed.
      t.datetime :cycle_started_at, null: false

      # 1 for a whole cycle; the share of one this segment covers otherwise.
      t.decimal :proration_ratio, precision: 30, scale: 10, null: false, default: 1

      t.enum :status, enum_type: :billing_segment_status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0

      t.timestamps

      # Idempotency backstop: one segment per (product, period). A re-pickup is a no-op
      # insert, never a double bill.
      t.index [:subscription_rate_card_id, :started_at],
        unique: true,
        name: "index_billing_segments_on_card_and_start"

      # Processor: find a subscription's pending segments for a billing moment.
      t.index [:subscription_id, :billing_at, :status]

      # Group a card's segments by the cycle they belong to, index-only.
      t.index [:subscription_rate_card_id, :cycle_started_at]
    end

    # Two segments of the same card can never cover the same instant. The unique index
    # above catches an identical re-pickup; this catches a regenerated window that
    # merely overlaps one already billed.
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<~SQL
            ALTER TABLE billing_segments
            ADD CONSTRAINT billing_segments_no_overlapping_windows
            EXCLUDE USING gist (
              organization_id WITH =,
              subscription_id WITH =,
              customer_id WITH =,
              subscription_rate_card_id WITH =,
              tsrange(started_at, ended_at, '[]') WITH &&
            )
          SQL
        end
      end
    end
  end
end
