# frozen_string_literal: true

require "rails_helper"

# Pins the activity_object of every catalog resource. The v2 REST endpoints render through
# the same serializers, so a key that a REST change adds, drops or renames fails here.
RSpec.describe Utils::ActivityLog, :capture_kafka_messages do
  subject(:produce) { described_class.produce(record, activity_type) { BaseService::Result.new } }

  let(:activity_log) { JSON.parse(kafka_messages.sole[:payload], symbolize_names: true) }
  let(:timestamp) { "2026-03-22T12:00:00Z" }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }
  let(:product_category) do
    create(
      :product_category,
      organization:,
      name: "Compute",
      code: "compute",
      description: "Compute products",
      invoice_display_name: "Compute usage"
    )
  end
  let(:product) do
    create(
      :product,
      organization:,
      product_category:,
      billable_metric:,
      name: "API",
      code: "api",
      description: "API product",
      invoice_display_name: "API calls"
    )
  end
  let(:product_filter) do
    create(
      :product_filter,
      organization:,
      product:,
      name: "US",
      code: "us",
      description: "US traffic",
      invoice_display_name: "US calls"
    )
  end

  before do
    travel_to(Time.zone.parse("2026-03-22 12:00:00"))
    allow(described_class).to receive(:available?).and_return(true)
  end

  context "with a catalog plan" do
    let(:record) { catalog_plan }
    let(:activity_type) { "plan.created" }
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
      create_list(:plan_rate_card, 2, organization:, catalog_plan:)
      create(:plan_rate_card, organization:, catalog_plan:, deleted_at: Time.current)
    end

    it "serializes the plan with the count of its kept rate cards" do
      produce

      expect(activity_log[:activity_object]).to eq(
        lago_id: catalog_plan.id,
        name: "Premium",
        invoice_display_name: "Premium plan",
        code: "premium",
        description: "Premium description",
        currency: "EUR",
        applied_rate_cards_count: 2,
        created_at: timestamp
      )
    end
  end

  context "with a product" do
    let(:record) { product }
    let(:activity_type) { "product.created" }

    before do
      create_list(:product_filter, 2, organization:, product:)
      create(:product_filter, organization:, product:, deleted_at: Time.current)
    end

    it "serializes the product with the count of its kept filters" do
      produce

      expect(activity_log[:activity_object]).to eq(
        lago_id: product.id,
        product_category_code: "compute",
        billable_metric_code: "api_calls",
        name: "API",
        code: "api",
        description: "API product",
        invoice_display_name: "API calls",
        product_type: "metered",
        filters_count: 2,
        created_at: timestamp,
        updated_at: timestamp
      )
    end
  end

  context "with a product category" do
    let(:record) { product_category }
    let(:activity_type) { "product_category.created" }

    before do
      create_list(:product, 2, organization:, product_category:)
      create(:product, organization:, product_category:, deleted_at: Time.current)
    end

    it "serializes the category with the count of its kept products" do
      produce

      expect(activity_log[:activity_object]).to eq(
        lago_id: product_category.id,
        name: "Compute",
        code: "compute",
        description: "Compute products",
        invoice_display_name: "Compute usage",
        products_count: 2,
        created_at: timestamp,
        updated_at: timestamp
      )
    end
  end

  context "with a product filter" do
    let(:record) { product_filter }
    let(:activity_type) { "product_filter.created" }
    let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu]) }
    let(:cloud) { create(:billable_metric_filter, billable_metric:, key: "cloud", values: %w[aws gcp]) }

    before do
      # Values are listed by creation time.
      create(:product_filter_value, organization:, product_filter:, billable_metric_filter: region, value: "us", created_at: 2.minutes.ago)
      create(:product_filter_value, organization:, product_filter:, billable_metric_filter: cloud, value: nil, created_at: 1.minute.ago)
      create(:product_filter_value, organization:, product_filter:, billable_metric_filter: region, value: "eu", deleted_at: Time.current)
    end

    it "serializes the filter with its kept values" do
      produce

      expect(activity_log[:activity_object]).to eq(
        lago_id: product_filter.id,
        name: "US",
        code: "us",
        description: "US traffic",
        invoice_display_name: "US calls",
        values: [
          {key: "region", value: "us"},
          {key: "cloud", value: nil}
        ],
        created_at: timestamp,
        updated_at: timestamp
      )
    end
  end

  context "with a rate card" do
    let(:record) { rate_card }
    let(:activity_type) { "rate_card.created" }
    let(:rate_card) do
      create(
        :rate_card,
        organization:,
        product:,
        product_filter:,
        name: "US API calls",
        code: "api_us",
        description: "API calls from the US",
        currency: "EUR"
      )
    end
    let(:vat) { create(:tax, organization:, name: "VAT", code: "vat", rate: 20.0, description: "French VAT") }
    let(:gst) { create(:tax, organization:, name: "GST", code: "gst", rate: 5.0, description: "Canadian GST") }

    # Created in effective_from order, because a rate can only be appended after the active one.
    let!(:terminated_rate) { create(:rate_card_rate, organization:, rate_card:, code: "launch", effective_from: Time.zone.parse("2026-01-01")) }
    let!(:active_rate) { create(:rate_card_rate, organization:, rate_card:, code: "current", effective_from: Time.zone.parse("2026-02-01")) }
    let!(:pending_rate) { create(:rate_card_rate, organization:, rate_card:, code: "next", effective_from: Time.zone.parse("2026-04-01")) }

    let(:rate_payloads) do
      [
        rate_payload(terminated_rate, code: "launch", effective_from: "2026-01-01T00:00:00Z", status: "terminated"),
        rate_payload(active_rate, code: "current", effective_from: "2026-02-01T00:00:00Z", status: "active"),
        rate_payload(pending_rate, code: "next", effective_from: "2026-04-01T00:00:00Z", status: "pending")
      ]
    end

    before do
      # Discarded where it would otherwise be the active rate.
      create(:rate_card_rate, organization:, rate_card:, code: "dropped", effective_from: Time.zone.parse("2026-03-01"), deleted_at: Time.current)

      create(:rate_card_applied_tax, organization:, rate_card:, tax: vat)
      create(:rate_card_applied_tax, organization:, rate_card:, tax: gst)
      create(:rate_card_applied_tax, organization:, rate_card:, tax: create(:tax, organization:, deleted_at: Time.current))
    end

    def rate_payload(rate, code:, effective_from:, status:)
      {
        lago_id: rate.id,
        code:,
        effective_from:,
        status:,
        rate_model: "standard",
        rate_properties: {amount: "10"},
        min_amount_cents: 0,
        billing_interval_count: 1,
        billing_interval_unit: "month",
        applied_pricing_unit_conversion_rate: nil,
        created_at: timestamp,
        updated_at: timestamp
      }
    end

    it "serializes the card with its kept rates and its kept taxes in the V1 shape" do
      produce

      expect(activity_log[:activity_object]).to match(
        lago_id: rate_card.id,
        product_code: "api",
        product_filter_code: "us",
        name: "US API calls",
        code: "api_us",
        description: "API calls from the US",
        currency: "EUR",
        billing_timing: "arrears",
        proration: false,
        display_on_invoice: true,
        regroup_paid_fees: nil,
        applied_pricing_unit_code: nil,
        rates_count: 3,
        created_at: timestamp,
        updated_at: timestamp,
        taxes: match_array([
          {
            lago_id: vat.id,
            name: "VAT",
            code: "vat",
            rate: 20.0,
            description: "French VAT",
            applied_to_organization: false,
            add_ons_count: 0,
            customers_count: 0,
            plans_count: 0,
            charges_count: 0,
            commitments_count: 0,
            created_at: timestamp
          },
          {
            lago_id: gst.id,
            name: "GST",
            code: "gst",
            rate: 5.0,
            description: "Canadian GST",
            applied_to_organization: false,
            add_ons_count: 0,
            customers_count: 0,
            plans_count: 0,
            charges_count: 0,
            commitments_count: 0,
            created_at: timestamp
          }
        ]),
        rates: match_array(rate_payloads)
      )
    end

    context "when a rate is added" do
      subject(:produce) do
        described_class.produce(rate_card, "rate_card.updated") do
          added_rate
          BaseService::Result.new
        end
      end

      let(:added_rate) { create(:rate_card_rate, organization:, rate_card:, code: "later", effective_from: Time.zone.parse("2026-05-01")) }

      it "logs the rates count and the rates as the only changes" do
        produce

        expect(activity_log[:activity_object_changes]).to match(
          rates_count: [3, 4],
          rates: [
            match_array(rate_payloads),
            match_array([
              *rate_payloads,
              rate_payload(added_rate, code: "later", effective_from: "2026-05-01T00:00:00Z", status: "pending")
            ])
          ]
        )
      end
    end
  end

  context "with a deleted product" do
    let(:record) { product }
    let(:activity_type) { "product.deleted" }

    before { product.discard! }

    it "serializes the product without its deletion date" do
      produce

      expect(activity_log[:activity_object]).to eq(
        lago_id: product.id,
        product_category_code: "compute",
        billable_metric_code: "api_calls",
        name: "API",
        code: "api",
        description: "API product",
        invoice_display_name: "API calls",
        product_type: "metered",
        filters_count: 0,
        created_at: timestamp,
        updated_at: timestamp
      )
    end
  end
end
