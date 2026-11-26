# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_plan_rate_cards view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card:, units: 2.5) }
  let(:deleted_plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, deleted_at: Time.current) }

  let(:result) { ActiveRecord::Base.connection.select_all("SELECT * FROM exports_plan_rate_cards") }

  def row_for(plan_rate_card)
    result.to_a.find { |row| row["lago_id"] == plan_rate_card.id }.symbolize_keys
  end

  before do
    plan_rate_card
    deleted_plan_rate_card
  end

  it "exposes the expected columns" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        lago_catalog_plan_id
        lago_rate_card_id
        units
        created_at
        updated_at
        deleted_at
      ]
    )
  end

  it "exports the plan rate card with its catalog plan and rate card" do
    plan_rate_card.reload

    expect(row_for(plan_rate_card)).to eq(
      organization_id: organization.id,
      lago_id: plan_rate_card.id,
      lago_catalog_plan_id: catalog_plan.id,
      lago_rate_card_id: rate_card.id,
      units: BigDecimal("2.5"),
      created_at: plan_rate_card.created_at,
      updated_at: plan_rate_card.updated_at,
      deleted_at: nil
    )
  end

  it "keeps soft-deleted plan rate cards with their deleted_at" do
    expect(row_for(deleted_plan_rate_card)).to include(
      units: nil,
      deleted_at: PlanRateCard.with_discarded.find(deleted_plan_rate_card.id).deleted_at
    )
  end
end
