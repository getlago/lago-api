# frozen_string_literal: true

class CreateContracts < ActiveRecord::Migration[8.0]
  def change
    create_enum :contract_status, %w[pending active terminated canceled]
    create_enum :contract_billing_time, %w[calendar anniversary]

    create_table :contracts, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: true
      # Nullable by design: a contract can price through directly attached
      # rate cards without any plan (the plan-less shape).
      t.references :plan, type: :uuid, null: true, foreign_key: true, index: true

      t.string :external_id, null: false
      t.string :name
      t.enum :status, enum_type: :contract_status, null: false, default: "pending"
      t.enum :billing_time, enum_type: :contract_billing_time, null: false, default: "calendar"

      t.date :billing_anchor_date
      # The validity window of the agreement: charges can be processed between
      # started_at and ended_at. Set at signature, future for an upcoming
      # contract — the lifecycle state lives in status, never in these dates.
      t.timestamp :started_at
      t.timestamp :ended_at
      t.timestamp :terminated_at
      t.timestamp :canceled_at

      t.timestamps

      t.index %i[organization_id external_id]
    end
  end
end
