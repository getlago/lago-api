# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::AdvanceChargesToDatetimeFilterResolver do
  subject(:relation) do
    described_class.new(billing_contexts: [billing_context], billing_at: Time.current).call
  end

  context "when the context is a contract" do
    let(:billing_context) { Billing::Context.from(contract: build_stubbed(:contract, status: :active)) }

    it "applies the charge boundary without looking for a next subscription" do
      expect(relation.to_sql).to include("charges_to_datetime")
    end
  end

  context "when an active subscription has a next subscription" do
    let(:subscription) { build_stubbed(:subscription, status: :active) }
    let(:billing_context) { Billing::Context.from(subscription:) }

    before do
      allow(subscription).to receive(:next_subscription).and_return(build_stubbed(:subscription))
    end

    it "does not apply the regular periodic charge boundary" do
      expect(relation.to_sql).not_to include("charges_to_datetime")
    end

    it "scopes eligible fees to the customer's subscription lineage and succeeded payment" do
      expect(relation.to_sql).to include("customer_id", "external_id", "status", "invoice_id", "payment_status", "succeeded_at")
    end
  end

  context "when resolving product fees for adjacent billing segments" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:product) { create(:product, :metered, organization:, billable_metric: create(:billable_metric, organization:)) }
    let(:rate_card) do
      create(:rate_card, :advance, :with_filter, organization:, product:, currency: "USD",
        display_on_invoice: false, regroup_paid_fees: :invoice)
    end
    let(:contract) { create(:contract, organization:, customer:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
    let(:august_segment) { build_segment("2026-08-01 00:00:00.000000", "2026-08-31 23:59:59.999999") }
    let(:september_segment) { build_segment("2026-09-01 00:00:00.000000", "2026-09-30 23:59:59.999999") }
    let(:august_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: august_segment) }
    let(:september_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: september_segment) }
    let(:august_fee) { create_product_fee(august_item) }
    let(:september_fee) { create_product_fee(september_item) }
    let(:fee_without_start_boundary) do
      create_product_fee(august_item, properties: august_item.filtered_for_charge_boundaries.except("charges_from_datetime"))
    end
    let(:resolver) do
      described_class.new(billing_contexts: [], billing_at: Time.current, metered_items: [august_item, september_item])
    end

    before do
      august_fee
      september_fee
      fee_without_start_boundary
    end

    it "selects fees by inclusive microsecond-precision segment boundaries" do
      expect(resolver.call).to match_array([august_fee, september_fee])
      expect(resolver.call).not_to include(fee_without_start_boundary)
      expect(described_class.new(billing_contexts: [], billing_at: Time.current, metered_items: [august_item]).call)
        .to contain_exactly(august_fee)
      expect(described_class.new(billing_contexts: [], billing_at: Time.current, metered_items: [september_item]).call)
        .to contain_exactly(september_fee)
    end

    it "does not mark an adjacent empty segment as invoiced from another segment's fee" do
      august_only_fees = described_class.new(
        billing_contexts: [], billing_at: Time.current, metered_items: [august_item]
      ).call

      expect(resolver.metered_items_with_fees(august_only_fees)).to eq([august_item])
    end

    def build_segment(started_at, ended_at)
      started_at = Time.zone.parse(started_at)
      ended_at = Time.zone.parse(ended_at)

      create(
        :billing_segment,
        organization:, customer:, contract:, contract_rate_card:, rate_card_rate:,
        currency: "USD", billing_at: ended_at, cycle_started_at: started_at,
        started_at:, ended_at:, status: :processing
      )
    end

    def create_product_fee(metered_item, properties: metered_item.filtered_for_charge_boundaries)
      segment = metered_item.billing_segment

      create(
        :fee, :succeeded, invoice: nil, subscription: nil, organization:,
        billing_entity: customer.billing_entity, contract:, contract_rate_card:,
        rate_card_rate:, invoiceable: product, product_filter: rate_card.product_filter,
        fee_type: :product, amount_currency: "USD", pay_in_advance: true,
        succeeded_at: segment.ended_at,
        properties:
      )
    end
  end
end
