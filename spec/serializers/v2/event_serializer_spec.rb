# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::EventSerializer do
  subject(:payload) { described_class.new(event, includes: [:usec_timestamps]).serialize }

  let(:event) do
    build_stubbed(:event, organization_id: SecureRandom.uuid, external_subscription_id: "contract.eu", transaction_id: "transaction.eu",
      code: "api.requests", customer_id: nil, precise_total_amount_cents: "123.45", properties: {"region" => "eu"})
  end

  it "serializes the stored event with contract terminology and no relationships" do
    expect(payload).to eq(
      lago_id: event.id,
      transaction_id: "transaction.eu",
      lago_customer_id: nil,
      external_contract_id: "contract.eu",
      code: "api.requests",
      precise_total_amount_cents: "123.45",
      properties: {"region" => "eu"},
      timestamp: event.timestamp.iso8601(6),
      created_at: event.created_at.iso8601(6),
      updated_at: event.updated_at.iso8601(6),
      deleted_at: nil
    )
  end

  context "with an unsaved ClickHouse ingestion event" do
    let(:event) do
      build(:event, organization_id: SecureRandom.uuid, external_subscription_id: "contract.eu", transaction_id: "transaction.eu",
        code: "api.requests", precise_total_amount_cents: nil, properties: {})
    end

    it "does not invent persistence timestamps or ids" do
      expect(payload).to eq(
        lago_id: nil,
        transaction_id: "transaction.eu",
        lago_customer_id: nil,
        external_contract_id: "contract.eu",
        code: "api.requests",
        precise_total_amount_cents: nil,
        properties: {},
        timestamp: event.timestamp.iso8601(6),
        created_at: nil,
        updated_at: nil,
        deleted_at: nil
      )
    end
  end
end
