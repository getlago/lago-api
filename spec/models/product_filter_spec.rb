# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductFilter do
  subject(:product_filter) { build(:product_filter) }

  it_behaves_like "paper_trail traceable"

  it_behaves_like "a catalog code", :product_filter

  describe "associations" do
    it do
      expect(product_filter).to belong_to(:organization)
      expect(product_filter).to belong_to(:product)
      expect(product_filter).to have_many(:values).class_name("ProductFilterValue")
      expect(product_filter).to have_many(:billable_metric_filters).through(:values)
      expect(product_filter).to have_many(:rate_cards)
      expect(product_filter).to have_many(:contract_alerts).class_name("UsageMonitoring::ContractAlert")
    end

    context "with contract alerts" do
      let(:product_filter) { create(:product_filter) }
      let(:organization) { product_filter.organization }
      let(:product) { product_filter.product }
      let(:alert) { create(:contract_usage_units_alert, organization:, product:, product_filter:) }

      before do
        alert
        create(
          :contract_usage_units_alert,
          organization:, product:, product_filter:, code: "discarded", deleted_at: Time.current
        )
        create(:contract_usage_units_alert, organization:, product:)
        create(:contract_usage_units_alert, organization: create(:organization), product:, product_filter:)
      end

      it "lists the kept alerts on the filter in its organization only" do
        expect(product_filter.contract_alerts).to eq([alert])
      end
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code) }

    describe "code uniqueness per product" do
      it "rejects a duplicate code on the same product" do
        existing = create(:product_filter)
        duplicate = build(
          :product_filter,
          organization: existing.organization,
          product: existing.product,
          code: existing.code
        )
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code on a different product" do
        existing = create(:product_filter)
        other = build(:product_filter, organization: existing.organization, code: existing.code)
        other.valid?
        expect(other.errors.where(:code, :taken)).not_to be_present
      end
    end
  end

  describe "#invoice_name" do
    it "returns the invoice_display_name when present" do
      filter = build_stubbed(:product_filter, invoice_display_name: "Display", name: "Name")
      expect(filter.invoice_name).to eq("Display")
    end

    it "falls back to name when invoice_display_name is blank" do
      filter = build_stubbed(:product_filter, invoice_display_name: nil, name: "Name")
      expect(filter.invoice_name).to eq("Name")
    end
  end

  describe "#to_h" do
    it "groups values by billable metric filter key" do
      filter = create(:product_filter)
      region = create(:billable_metric_filter, organization: filter.organization, key: "region", values: %w[us eu])
      scheme = create(:billable_metric_filter, organization: filter.organization, key: "scheme", values: %w[visa])
      create(:product_filter_value, product_filter: filter, organization: filter.organization, billable_metric_filter: region, value: "us")
      create(:product_filter_value, product_filter: filter, organization: filter.organization, billable_metric_filter: region, value: "eu")
      create(:product_filter_value, product_filter: filter, organization: filter.organization, billable_metric_filter: scheme, value: "visa")

      expect(filter.reload.to_h).to eq("region" => %w[us eu], "scheme" => %w[visa])
      expect(filter.to_h_with_all_values).to eq("region" => %w[us eu], "scheme" => %w[visa])
    end
  end

  describe "#to_h_with_all_values" do
    it "expands nil to configured values without changing the raw hash" do
      filter = create(:product_filter)
      region = create(:billable_metric_filter, organization: filter.organization, key: "region", values: %w[us eu])
      create(:product_filter_value, product_filter: filter, organization: filter.organization, billable_metric_filter: region, value: nil)

      expect(filter.to_h).to eq("region" => [nil])
      expect(filter.to_h_with_all_values).to eq("region" => %w[us eu])
      expect(filter.to_h).to eq("region" => [nil])
    end

    it "returns empty raw and expanded hashes for a filter without values" do
      expect(product_filter.to_h).to eq({})
      expect(product_filter.to_h_with_all_values).to eq({})
    end
  end

  describe "#attached_to_subscriptions?" do
    let(:filter) { create(:product_filter) }
    let(:rate_card) { create(:rate_card, organization: filter.organization, product: filter.product, product_filter: filter) }
    let(:status) { :active }

    before do
      customer = create(:customer, organization: filter.organization)
      contract = create(:contract, status, organization: filter.organization, customer:)
      create(:contract_rate_card, organization: filter.organization, contract:, rate_card:)
    end

    it "is true when a contract prices the filter" do
      expect(filter.attached_to_subscriptions?).to be(true)
    end

    context "when that contract is canceled" do
      let(:status) { :canceled }

      it "is false, as a canceled contract never took effect" do
        expect(filter.attached_to_subscriptions?).to be(false)
      end
    end
  end

  describe "#attached_to_plan_or_subscription?" do
    let(:product) { create(:product) }
    let(:filter) { create(:product_filter, organization: product.organization, product:) }

    it "delegates to the product" do
      expect(filter.attached_to_plan_or_subscription?).to be(false)

      create(:contract_rate_card, organization: product.organization, product:)

      expect(filter.attached_to_plan_or_subscription?).to be(true)
    end
  end
end
