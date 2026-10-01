# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Plans::DeletedService do
  subject(:webhook_service) { described_class.new(object: plan) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "plan.deleted", "plan"

    context "when the object is a catalog plan" do
      subject(:webhook_service) { described_class.new(object: catalog_plan) }

      let(:catalog_plan) do
        create(
          :catalog_plan,
          organization:,
          name: "Premium",
          invoice_display_name: "Premium plan",
          code: "premium",
          description: "Premium description",
          currency: "EUR"
        )
      end

      before do
        travel_to(Time.zone.parse("2026-03-22 12:00:00"))
        # As the destroy service leaves them: its rate cards and the plan itself discarded.
        create(:plan_rate_card, organization:, catalog_plan:, deleted_at: Time.current)
        catalog_plan.discard!
      end

      it "sends the catalog plan payload without its deletion date" do
        webhook_service.call

        expect(organization.webhooks.sole.payload).to eq(
          "webhook_type" => "plan.deleted",
          "object_type" => "plan",
          "organization_id" => organization.id,
          "plan" => {
            "lago_id" => catalog_plan.id,
            "name" => "Premium",
            "invoice_display_name" => "Premium plan",
            "code" => "premium",
            "description" => "Premium description",
            "currency" => "EUR",
            "applied_rate_cards_count" => 0,
            "created_at" => "2026-03-22T12:00:00Z"
          }
        )
      end
    end
  end
end
