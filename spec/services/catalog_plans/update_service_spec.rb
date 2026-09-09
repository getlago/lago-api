# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlans::UpdateService do
  subject(:result) { described_class.call(catalog_plan:, params:) }

  let(:catalog_plan) { create(:catalog_plan, name: "Before", code: "before") }
  let(:params) { {name: "After", code: "after"} }

  it "updates the catalog plan" do
    expect(result).to be_success
    expect(result.catalog_plan.reload).to have_attributes(name: "After", code: "after")
  end

  it "enqueues a plan.updated webhook" do
    result

    expect(SendWebhookJob).to have_been_enqueued.with("plan.updated", catalog_plan)
  end

  context "when send_webhook is false" do
    it "does not enqueue the webhook but still produces the activity log" do
      described_class.call(catalog_plan:, params:, send_webhook: false)

      expect(SendWebhookJob).not_to have_been_enqueued.with("plan.updated", catalog_plan)
      expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(catalog_plan)
    end
  end

  context "when the catalog plan is missing" do
    let(:catalog_plan) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when the update is invalid" do
    let(:params) { {currency: "INVALID"} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end

    it "emits no webhook and no activity log" do
      result

      expect(SendWebhookJob).not_to have_been_enqueued
      expect(Utils::ActivityLog).not_to have_produced("plan.updated")
    end
  end

  context "when changing the currency of a plan holding applied rate cards" do
    let(:catalog_plan) { create(:catalog_plan, currency: "EUR") }
    let(:params) { {currency: "USD"} }

    before { create(:plan_rate_card, organization: catalog_plan.organization, catalog_plan:) }

    it "rejects the change" do
      expect(result).not_to be_success
      expect(result.error.messages[:currency]).to eq(["not_editable_with_applied_rate_cards"])
    end

    it "still allows editing other attributes" do
      result = described_class.call(catalog_plan:, params: {name: "Renamed"})

      expect(result).to be_success
      expect(result.catalog_plan.reload.name).to eq("Renamed")
    end
  end

  context "when changing the currency of a plan attached to a contract with direct rate cards" do
    let(:catalog_plan) { create(:catalog_plan, currency: "EUR") }
    let(:params) { {currency: "USD"} }

    before do
      customer = create(:customer, organization: catalog_plan.organization)
      contract = create(:contract, organization: catalog_plan.organization, customer:, catalog_plan:)
      create(:contract_rate_card, organization: catalog_plan.organization, contract:)
    end

    it "rejects the change even without plan-level rate cards" do
      expect(catalog_plan.applied_rate_cards).to be_empty
      expect(result).not_to be_success
      expect(result.error.messages[:currency]).to eq(["not_editable_with_applied_rate_cards"])
    end
  end
end
