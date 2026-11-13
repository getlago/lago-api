# frozen_string_literal: true

require "rails_helper"

describe PlanWalletsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization:) }
  let_it_be(:plan_wallet) { create(:plan_wallet, organization:, catalog_plan:, created_at: Time.zone.parse("2026-10-03 10:00:00")) }
  let_it_be(:older_plan_wallet) { create(:plan_wallet, organization:, catalog_plan:, created_at: Time.zone.parse("2026-10-01 10:00:00")) }
  let_it_be(:other_plan_wallet) { create(:plan_wallet, organization:, created_at: Time.zone.parse("2026-10-02 10:00:00")) }

  let(:pagination) { nil }
  let(:filters) { {} }

  before_all do
    create(:plan_wallet, organization:, catalog_plan:, deleted_at: Time.current)
    create(:plan_wallet, organization: create(:organization))
  end

  it "returns the kept wallet templates of the organization, the latest first" do
    expect(result).to be_success
    expect(result.plan_wallets).to eq([plan_wallet, other_plan_wallet, older_plan_wallet])
  end

  context "when filtering by plan_id" do
    let(:filters) { {plan_id: catalog_plan.id} }

    it "returns only the plan's wallet templates" do
      expect(result.plan_wallets).to eq([plan_wallet, older_plan_wallet])
    end
  end

  context "when filtering by created_at" do
    let(:filters) { {created_at_from: "2026-10-02", created_at_to: "2026-10-03T10:00:00Z"} }

    it "returns the wallet templates created in the range, bounds included" do
      expect(result.plan_wallets).to eq([plan_wallet, other_plan_wallet])
    end

    context "when a bound is not a date" do
      let(:filters) { {created_at_from: "2026-13-01"} }

      it "fails on that filter" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq({created_at_from: ["invalid_date"]})
      end
    end
  end

  context "with a page size" do
    let(:pagination) { {page: 1, limit: 2} }

    it "returns that many wallet templates" do
      expect(result.plan_wallets).to eq([plan_wallet, other_plan_wallet])
    end
  end
end
