# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePhases::CreateService do
  subject(:result) { described_class.call(plan_product_item:, params:) }

  let(:organization) { create(:organization) }
  let(:plan_product_item) { create(:plan_product_item, organization:) }

  let(:params) { {position: 1, billing_interval_cycle_count: 6, name: "Trial period"} }

  it "creates a rate phase" do
    expect { result }.to change(RatePhase, :count).by(1)

    rate_phase = result.rate_phase
    expect(rate_phase.plan_product_item).to eq(plan_product_item)
    expect(rate_phase.organization).to eq(organization)
    expect(rate_phase.position).to eq(1)
    expect(rate_phase.billing_interval_cycle_count).to eq(6)
    expect(rate_phase.name).to eq("Trial period")
  end

  context "when no parent is provided" do
    subject(:result) { described_class.call(params:) }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
