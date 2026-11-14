# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Plans::EntitlementsUpdatedService do
  subject(:webhook_service) { described_class.new(object: catalog_plan) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
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
  let(:tax) { create(:tax, organization:, name: "VAT", code: "vat", rate: 20.0, description: "French VAT") }
  let(:seats) { create(:feature, organization:, code: "seats") }
  let(:sso) { create(:feature, organization:, code: "sso") }
  let(:seats_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: seats) }
  let(:sso_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: sso) }

  before do
    travel_to(Time.zone.parse("2026-03-22 12:00:00"))
    create(:plan_rate_card, organization:, catalog_plan:)
    create(:plan_rate_card, organization:, catalog_plan:, deleted_at: Time.current)
    create(:plan_applied_tax, :catalog_plan, organization:, catalog_plan:, tax:)

    max = create(:privilege, :integer_type, organization:, feature: seats, code: "max")
    tier = create(:privilege, :string_type, organization:, feature: seats, code: "tier")
    seats_entitlement
    create(:entitlement_value, organization:, entitlement: seats_entitlement, privilege: max, value: "50")
    create(:entitlement_value, organization:, entitlement: seats_entitlement, privilege: tier, value: "silver",
      deleted_at: Time.current)
    travel(1.second)
    create(:entitlement_value, organization:, entitlement: seats_entitlement, privilege: tier, value: "gold")

    travel_to(Time.zone.parse("2026-03-22 13:00:00"))
    enabled = create(:privilege, :boolean_type, organization:, feature: sso, code: "enabled")
    create(:entitlement_value, organization:, entitlement: sso_entitlement, privilege: enabled, value: "true")
    create(:entitlement, :catalog_plan, organization:, catalog_plan:, deleted_at: Time.current)
  end

  describe ".call" do
    it "sends the catalog plan as plan.updated does, with its kept entitlements oldest first" do
      webhook_service.call

      expect(organization.webhooks.sole.payload).to eq(
        "webhook_type" => "plan.entitlements_updated",
        "object_type" => "plan",
        "organization_id" => organization.id,
        "plan" => {
          "lago_id" => catalog_plan.id,
          "name" => "Premium",
          "invoice_display_name" => "Premium plan",
          "code" => "premium",
          "description" => "Premium description",
          "currency" => "EUR",
          "applied_rate_cards_count" => 1,
          "created_at" => "2026-03-22T12:00:00Z",
          "deleted_at" => nil,
          "taxes" => [
            {
              "lago_id" => tax.id,
              "name" => "VAT",
              "code" => "vat",
              "rate" => 20.0,
              "description" => "French VAT",
              "created_at" => "2026-03-22T12:00:00Z",
              "updated_at" => "2026-03-22T12:00:00Z",
              "deleted_at" => nil
            }
          ],
          "entitlements" => [
            {
              "lago_id" => seats_entitlement.id,
              "plan_code" => "premium",
              "feature_code" => "seats",
              "values" => [
                {"privilege_code" => "max", "value" => 50},
                {"privilege_code" => "tier", "value" => "gold"}
              ],
              "created_at" => "2026-03-22T12:00:00Z",
              "updated_at" => "2026-03-22T12:00:01Z", # touched by the gold value, created a second later
              "deleted_at" => nil
            },
            {
              "lago_id" => sso_entitlement.id,
              "plan_code" => "premium",
              "feature_code" => "sso",
              "values" => [{"privilege_code" => "enabled", "value" => true}],
              "created_at" => "2026-03-22T13:00:00Z",
              "updated_at" => "2026-03-22T13:00:00Z",
              "deleted_at" => nil
            }
          ]
        }
      )
    end

    it "sends the http webhook" do
      expect { webhook_service.call }.to have_enqueued_job(SendHttpWebhookJob)
    end

    context "when the organization has no product catalog" do
      let(:organization) { create(:organization) }

      it "creates no webhook" do
        expect { webhook_service.call }.not_to change(Webhook, :count)
      end
    end

    context "when the endpoint subscribes to other event types only" do
      before { organization.webhook_endpoints.sole.update!(event_types: ["plan.updated"]) }

      it "creates no webhook" do
        expect { webhook_service.call }.not_to change(Webhook, :count)
      end
    end

    context "when the endpoint subscribes to the event type" do
      before { organization.webhook_endpoints.sole.update!(event_types: ["plan.entitlements_updated"]) }

      it "creates the webhook" do
        webhook_service.call

        expect(organization.webhooks.sole.webhook_type).to eq("plan.entitlements_updated")
      end
    end
  end
end
