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
          name: "Startup",
          invoice_display_name: "Startup plan",
          code: "startup",
          description: "Plan for startups",
          currency: "USD",
          deleted_at: Time.current
        )
      end
      let(:tax) { create(:tax, organization:, name: "VAT", code: "vat_20", rate: 20.0, description: "Standard VAT") }

      before { create(:plan_applied_tax, :catalog_plan, catalog_plan:, tax:, organization:) }

      it "creates a webhook with every serialized catalog plan field" do
        webhook_service.call

        webhook = Webhook.order(created_at: :desc).first
        expect(webhook.payload).to eq(
          "webhook_type" => "plan.deleted",
          "object_type" => "plan",
          "organization_id" => organization.id,
          "plan" => {
            "lago_id" => catalog_plan.id,
            "name" => "Startup",
            "invoice_display_name" => "Startup plan",
            "code" => "startup",
            "description" => "Plan for startups",
            "currency" => "USD",
            "applied_rate_cards_count" => 0,
            "created_at" => catalog_plan.created_at.iso8601,
            "taxes" => [
              {
                "lago_id" => tax.id,
                "name" => "VAT",
                "code" => "vat_20",
                "rate" => 20.0,
                "description" => "Standard VAT",
                "applied_to_organization" => false,
                "add_ons_count" => 0,
                "customers_count" => 0,
                "plans_count" => 0,
                "charges_count" => 0,
                "commitments_count" => 0,
                "created_at" => tax.created_at.iso8601
              }
            ]
          }
        )
      end
    end
  end
end
