# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Snapshots::OneOffService do
  subject(:service) { described_class.new(quote_version:) }

  let(:organization) { create(:organization) }
  let(:quote) { create(:quote, organization:, order_type: :one_off) }
  let(:add_on) do
    create(
      :add_on,
      organization:,
      code: "setup",
      name: "Setup Fee",
      invoice_display_name: "One-time Setup",
      description: "Onboarding",
      amount_cents: 1_000
    )
  end
  let(:billing_items) do
    {
      "addons" => [
        {
          "id" => add_on.id,
          "local_id" => "row-1",
          "payload" => {"units" => 2, "unit_amount_cents" => 1_000, "from_datetime" => nil, "to_datetime" => nil},
          "overrides" => {"unit_amount_cents" => 1_200}
        }
      ]
    }
  end
  let(:quote_version) { create(:quote_version, quote:, organization:, currency: "EUR", billing_items:) }

  describe ".call" do
    let(:result) { service.call }
    let(:snapshot) { result.billing_items }
    let(:snapshotted_add_on) { snapshot["addons"].first }
    let(:payload) { snapshotted_add_on["payload"] }

    it "freezes the catalog fields into each add-on payload" do
      expect(result).to be_success
      expect(payload).to include(
        "code" => "setup",
        "name" => "Setup Fee",
        "invoice_display_name" => "One-time Setup",
        "description" => "Onboarding",
        "unit_amount_cents" => 1_000
      )
    end

    it "preserves the client deal terms and references verbatim" do
      expect(payload).to include("units" => 2, "from_datetime" => nil, "to_datetime" => nil)
      expect(snapshotted_add_on).to include(
        "id" => add_on.id,
        "local_id" => "row-1",
        "overrides" => {"unit_amount_cents" => 1_200}
      )
    end

    it "freezes unit_amount_cents to the catalog list price and keeps the override" do
      expect(payload["unit_amount_cents"]).to eq(1_000)
      expect(snapshotted_add_on["overrides"]["unit_amount_cents"]).to eq(1_200)
    end

    context "when the add-on has been soft-deleted" do
      before { add_on.discard }

      it "still freezes the discarded add-on's catalog fields" do
        expect(result).to be_success
        expect(payload).to include("code" => "setup", "unit_amount_cents" => 1_000)
      end
    end

    context "with several add-ons" do
      let(:other_add_on) { create(:add_on, organization:, code: "support", amount_cents: 500) }
      let(:billing_items) do
        {
          "addons" => [
            {"id" => add_on.id, "local_id" => "row-1", "payload" => {"units" => 1}},
            {"id" => other_add_on.id, "local_id" => "row-2", "payload" => {"units" => 1}}
          ]
        }
      end

      it "resolves all add-ons in a single query" do
        add_on
        other_add_on

        queries = []
        callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('FROM "add_ons"') }
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { service.call }

        expect(queries.size).to eq(1)
      end
    end

    context "when a referenced add-on cannot be resolved" do
      let(:billing_items) do
        {"addons" => [{"id" => SecureRandom.uuid, "local_id" => "row-1", "payload" => {"units" => 1}}]}
      end

      it "fails gracefully instead of raising" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
      end
    end
  end
end
