# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clickhouse::ActivityLog, clickhouse: true do
  subject(:activity_log) { create(:clickhouse_activity_log) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:resource) }
  it { is_expected.to belong_to(:customer).optional }
  it { is_expected.to belong_to(:subscription).optional }
  it { is_expected.to belong_to(:user).optional }
  it { is_expected.to belong_to(:api_key).optional }

  describe "activity and resource definitions" do
    it "defines the new product catalog activity types and resources" do
      expect(described_class::ACTIVITY_TYPES.slice(
        :rate_card_rate_created, :rate_card_rate_updated, :rate_card_rate_deleted,
        :plan_rate_card_created, :plan_rate_card_updated, :plan_rate_card_deleted,
        :contract_rate_card_created, :contract_rate_card_updated, :contract_rate_card_deleted,
        :contract_created, :contract_updated, :contract_started, :contract_terminated, :contract_canceled
      )).to eq(
        rate_card_rate_created: "rate_card_rate.created",
        rate_card_rate_updated: "rate_card_rate.updated",
        rate_card_rate_deleted: "rate_card_rate.deleted",
        plan_rate_card_created: "plan_rate_card.created",
        plan_rate_card_updated: "plan_rate_card.updated",
        plan_rate_card_deleted: "plan_rate_card.deleted",
        contract_rate_card_created: "contract_rate_card.created",
        contract_rate_card_updated: "contract_rate_card.updated",
        contract_rate_card_deleted: "contract_rate_card.deleted",
        contract_created: "contract.created",
        contract_updated: "contract.updated",
        contract_started: "contract.started",
        contract_terminated: "contract.terminated",
        contract_canceled: "contract.canceled"
      )

      expect(described_class::RESOURCE_TYPES.slice(:rate_card_rate, :plan_rate_card, :contract_rate_card, :contract)).to eq(
        rate_card_rate: "RateCardRate",
        plan_rate_card: "PlanRateCard",
        contract_rate_card: "ContractRateCard",
        contract: "Contract"
      )
      expect(described_class::RESOURCE_TYPES_WITH_DISCARDED).to include("RateCardRate", "PlanRateCard", "ContractRateCard")
    end
  end

  describe "#resource" do
    subject(:activity_log) do
      build(:clickhouse_activity_log, organization:, resource_type: "RateCardRate", resource_id: rate_card_rate.id)
    end

    let(:organization) { create(:organization) }
    let(:rate_card_rate) { create(:rate_card_rate, organization:) }
    let(:other_organization_rate) { create(:rate_card_rate) }
    let(:other_organization_log) do
      build(
        :clickhouse_activity_log,
        organization: other_organization_rate.organization,
        resource_type: "RateCardRate",
        resource_id: rate_card_rate.id
      )
    end

    before do
      rate_card_rate.discard
    end

    it "finds a discarded resource only in the activity log organization" do
      expect(activity_log.resource).to eq(rate_card_rate)
      expect(other_organization_log.resource).to be_nil
    end
  end

  describe "#ensure_activity_id" do
    it "sets the activity_id if it is not set" do
      expect(activity_log.activity_id).to be_present
    end
  end
end
