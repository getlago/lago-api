# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_contract_rate_cards_terms view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, effective_date: Date.new(2026, 2, 1)) }

  let(:term) do
    create(:contract_rate_card_term, organization:, contract_rate_card:, units: 2.5, effective_date: Date.new(2026, 2, 1))
  end
  let(:next_cycle_term) do
    create(
      :contract_rate_card_term,
      organization:,
      contract_rate_card:,
      units: 4,
      effective_date: Date.new(2026, 3, 1),
      application_timing: :next_billing_cycle
    )
  end

  let(:result) { ActiveRecord::Base.connection.select_all("SELECT * FROM exports_contract_rate_cards_terms") }

  def row_for(term)
    result.to_a.find { |row| row["lago_id"] == term.id }.symbolize_keys
  end

  before do
    term
    next_cycle_term
  end

  it "exposes the expected columns" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        lago_contract_rate_card_id
        units
        effective_date
        application_timing
        created_at
        updated_at
      ]
    )
  end

  it "exports the term with its contract rate card" do
    term.reload

    expect(row_for(term)).to eq(
      organization_id: organization.id,
      lago_id: term.id,
      lago_contract_rate_card_id: contract_rate_card.id,
      units: BigDecimal("2.5"),
      effective_date: Date.new(2026, 2, 1),
      application_timing: "current_billing_cycle",
      created_at: term.created_at,
      updated_at: term.updated_at
    )
  end

  it "exports the application timing as text" do
    expect(row_for(next_cycle_term)).to include(
      units: BigDecimal("4"),
      application_timing: "next_billing_cycle"
    )
  end
end
