# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_rate_phases view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:rate_override) { create(:rate_override, organization:) }

  let(:plan_rate_phase) do
    create(:rate_phase, organization:, name: "Intro", position: 1, billing_interval_cycle_count: 3, rate_override:)
  end

  let(:contract_rate_phase) { create(:rate_phase, :contract_level, organization:, position: 2) }
  let(:deleted_rate_phase) { create(:rate_phase, organization:, deleted_at: Time.current) }

  let(:result) do
    ActiveRecord::Base.connection.select_all("SELECT * FROM exports_rate_phases ORDER BY created_at, lago_id")
  end

  def row_for(record)
    result.to_a.find { |row| row["lago_id"] == record.id }
  end

  before do
    plan_rate_phase
    contract_rate_phase
    deleted_rate_phase
  end

  it "exports the columns in order" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        lago_plan_rate_card_id
        lago_contract_rate_card_id
        lago_rate_override_id
        code
        name
        position
        billing_interval_cycle_count
        created_at
        updated_at
        deleted_at
      ]
    )
  end

  it "exports plan rate phases with their override" do
    expect(row_for(plan_rate_phase)).to include(
      "organization_id" => organization.id,
      "lago_plan_rate_card_id" => plan_rate_phase.plan_rate_card_id,
      "lago_contract_rate_card_id" => nil,
      "lago_rate_override_id" => rate_override.id,
      "code" => plan_rate_phase.code,
      "name" => "Intro",
      "position" => 1,
      "billing_interval_cycle_count" => 3,
      "deleted_at" => nil
    )
  end

  it "exports contract rate phases with a null plan rate card" do
    expect(row_for(contract_rate_phase)).to include(
      "lago_plan_rate_card_id" => nil,
      "lago_contract_rate_card_id" => contract_rate_phase.contract_rate_card_id,
      "lago_rate_override_id" => nil,
      "position" => 2,
      "billing_interval_cycle_count" => nil
    )
  end

  it "exports soft-deleted rate phases with their deleted_at" do
    expect(row_for(deleted_rate_phase)["deleted_at"]).to be_present
  end
end
