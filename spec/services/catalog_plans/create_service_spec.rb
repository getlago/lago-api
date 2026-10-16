# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlans::CreateService do
  subject(:result) { described_class.call(args) }

  let(:organization) { create(:organization) }
  let(:args) do
    {
      organization_id: organization.id,
      name: "Growth",
      code: "growth",
      description: "Growth plan",
      invoice_display_name: "Growth",
      currency: "USD"
    }
  end

  it "creates a catalog plan" do
    expect { result }.to change(CatalogPlan, :count).by(1)

    expect(result).to be_success
    expect(result.catalog_plan).to have_attributes(
      organization_id: organization.id,
      name: "Growth",
      code: "growth",
      description: "Growth plan",
      invoice_display_name: "Growth",
      currency: "USD"
    )
  end

  it "enqueues a plan.created webhook" do
    result

    expect(SendWebhookJob).to have_been_enqueued.with("plan.created", result.catalog_plan)
  end

  context "when send_webhook is false" do
    it "does not enqueue the webhook but still produces the activity log" do
      result = described_class.call(args, send_webhook: false)

      expect(SendWebhookJob).not_to have_been_enqueued.with("plan.created", result.catalog_plan)
      expect(Utils::ActivityLog).to have_produced("plan.created").after_commit.with(result.catalog_plan)
    end
  end

  context "when the currency is invalid" do
    let(:args) { {organization_id: organization.id, name: "Growth", code: "growth", currency: "INVALID"} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages[:currency]).to be_present
    end

    it "emits no webhook and no activity log" do
      result

      expect(SendWebhookJob).not_to have_been_enqueued
      expect(Utils::ActivityLog).not_to have_produced("plan.created")
    end
  end
end
