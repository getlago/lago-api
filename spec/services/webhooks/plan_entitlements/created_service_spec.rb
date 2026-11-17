# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::PlanEntitlements::CreatedService do
  subject(:webhook_service) { described_class.new(object: entitlement) }

  let(:organization) { create(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:, code: "premium") }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:privilege) { create(:privilege, :integer_type, organization:, feature:, code: "max") }
  let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }

  before do
    allow(organization).to receive(:product_catalog_enabled?).and_return(true)
    create(:entitlement_value, organization:, entitlement:, privilege:, value: "50")
  end

  describe ".call" do
    it "creates a webhook with the plan entitlement only" do
      webhook_service.call

      entitlement.reload
      expect(Webhook.order(created_at: :desc).first.payload).to eq(
        "webhook_type" => "plan_entitlement.created",
        "object_type" => "plan_entitlement",
        "organization_id" => organization.id,
        "plan_entitlement" => {
          "lago_id" => entitlement.id,
          "plan_code" => "premium",
          "feature_code" => "seats",
          "values" => [{"privilege_code" => "max", "value" => 50}],
          "created_at" => entitlement.created_at.iso8601,
          "updated_at" => entitlement.updated_at.iso8601,
          "deleted_at" => nil
        }
      )
    end

    context "when the endpoint filter lacks the type" do
      before { organization.webhook_endpoints.sole.update!(event_types: ["plan_entitlement.updated"]) }

      it "creates no webhook" do
        expect { webhook_service.call }.not_to change(Webhook, :count)
      end
    end

    context "when the organization has no product catalog" do
      before { allow(organization).to receive(:product_catalog_enabled?).and_return(false) }

      it "creates no webhook" do
        expect { webhook_service.call }.not_to change(Webhook, :count)
      end
    end
  end
end
