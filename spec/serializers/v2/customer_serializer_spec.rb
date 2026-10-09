# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::CustomerSerializer do
  subject(:payload) { described_class.new(customer, includes:).serialize }

  let(:customer) do
    build_stubbed(
      :customer,
      billing_entity: build_stubbed(:billing_entity),
      customer_type: "company",
      sequential_id: 7,
      slug: "LAG-1234-007",
      tax_identification_number: "FR12345678901",
      timezone: "Europe/Paris",
      net_payment_term: 30,
      external_salesforce_id: "sf_001",
      finalize_zero_amount_invoice: "skip",
      skip_invoice_custom_sections: true,
      deleted_at:
    )
  end
  let(:deleted_at) { nil }
  let(:includes) { [] }
  # V1 always embeds these, while everything else it nests is an opt-in include.
  let(:v1_payload) { V1::CustomerSerializer.new(customer).serialize.except(:billing_configuration, :shipping_address, :metadata) }
  let(:scalar_keys) do
    %i[
      lago_id billing_entity_code external_id account_type name firstname lastname customer_type sequential_id slug
      created_at updated_at
      country address_line1 address_line2 state zipcode email city url phone logo_url
      legal_name legal_number currency tax_identification_number
      timezone applicable_timezone net_payment_term
      external_salesforce_id finalize_zero_amount_invoice skip_invoice_custom_sections
    ]
  end

  it "renders V1's scalar fields only, in V1 order" do
    expect(payload.keys).to eq(scalar_keys)
  end

  it "renders scalar values only" do
    expect(payload.values).to all(be_a(String).or(be_a(Integer)).or(be(true)).or(be(false)))
  end

  it "renders the same values as V1, without its nested objects" do
    expect(payload).to eq(v1_payload)
    expect(payload.keys).to eq(v1_payload.keys)
  end

  context "with deleted_at, for a discarded customer" do
    let(:includes) { %i[deleted_at] }
    let(:deleted_at) { Time.zone.parse("2026-09-30T12:00:00Z") }

    it "renders deleted_at last" do
      expect(payload.keys).to eq([*scalar_keys, :deleted_at])
      expect(payload[:deleted_at]).to eq("2026-09-30T12:00:00Z")
    end
  end
end
