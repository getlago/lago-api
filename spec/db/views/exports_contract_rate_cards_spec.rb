# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_contract_rate_cards view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:contract) { create(:contract, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }

  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      rate_card:,
      billing_anchor_date: Date.new(2026, 1, 15),
      effective_date: Date.new(2026, 2, 1),
      next_billing_at: Time.zone.parse("2026-03-15T00:00:00Z")
    )
  end
  let(:deleted_contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, deleted_at: Time.current)
  end

  let(:result) { ActiveRecord::Base.connection.select_all("SELECT * FROM exports_contract_rate_cards") }

  def row_for(contract_rate_card)
    result.to_a.find { |row| row["lago_id"] == contract_rate_card.id }.symbolize_keys
  end

  before do
    contract_rate_card
    deleted_contract_rate_card
  end

  it "exposes the expected columns" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        lago_contract_id
        lago_rate_card_id
        billing_anchor_date
        next_billing_at
        effective_date
        created_at
        updated_at
        deleted_at
      ]
    )
  end

  it "exports the contract rate card with its contract and rate card" do
    contract_rate_card.reload

    expect(row_for(contract_rate_card)).to eq(
      organization_id: organization.id,
      lago_id: contract_rate_card.id,
      lago_contract_id: contract.id,
      lago_rate_card_id: rate_card.id,
      billing_anchor_date: Date.new(2026, 1, 15),
      next_billing_at: Time.zone.parse("2026-03-15T00:00:00Z"),
      effective_date: Date.new(2026, 2, 1),
      created_at: contract_rate_card.created_at,
      updated_at: contract_rate_card.updated_at,
      deleted_at: nil
    )
  end

  it "keeps soft-deleted contract rate cards with their deleted_at" do
    expect(row_for(deleted_contract_rate_card)).to include(
      deleted_at: ContractRateCard.with_discarded.find(deleted_contract_rate_card.id).deleted_at
    )
  end
end
