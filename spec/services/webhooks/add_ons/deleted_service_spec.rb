# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::AddOns::DeletedService do
  subject(:webhook_service) { described_class.new(object: add_on) }

  let(:organization) { create(:organization) }
  let(:add_on) do
    create(
      :add_on,
      organization:,
      name: "Setup fee",
      invoice_display_name: "Setup",
      code: "setup_fee",
      description: "One-time setup",
      amount_cents: 12_000,
      amount_currency: "USD"
    )
  end
  let(:tax) { create(:tax, organization:, name: "VAT", code: "vat_20", rate: 20.0, description: "Standard VAT") }

  before { create(:add_on_applied_tax, add_on:, tax:) }

  describe ".call" do
    it "creates a webhook with every serialized add-on field" do
      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "add_on.deleted",
        "object_type" => "add_on",
        "organization_id" => organization.id,
        "add_on" => {
          "lago_id" => add_on.id,
          "name" => "Setup fee",
          "invoice_display_name" => "Setup",
          "code" => "setup_fee",
          "amount_cents" => 12_000,
          "amount_currency" => "USD",
          "created_at" => add_on.created_at.iso8601,
          "description" => "One-time setup",
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
