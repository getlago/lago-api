# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::PayInAdvanceMeteredItemsResolver do
  subject(:selections) { described_class.call!(event:).selections }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:timestamp) { Time.zone.parse("2026-09-17 15:00:00") }

  context "with a subscription" do
    let(:subscription) { create(:subscription, organization:, customer:, started_at: timestamp - 1.month) }
    let(:charge) { create(:standard_charge, :pay_in_advance, plan: subscription.plan, billable_metric:) }
    let(:event) do
      build(
        :common_event,
        organization_id: organization.id,
        code: billable_metric.code,
        external_subscription_id: subscription.external_id,
        timestamp:
      )
    end

    before { charge }

    it "returns the charge with its subscription context and boundaries" do
      selection = selections.sole

      expect(selection.billing_context.subscription).to eq(subscription)
      expect(selection.metered_item).to have_attributes(charge:, event:)
      expect(selection.metered_item.boundaries).to have_attributes(timestamp:)
    end
  end

  context "with an advance metered contract rate card" do
    let(:organization) { create(:organization, feature_flags: [:product_catalog]) }
    let(:contract) { create(:contract, organization:, customer:) }
    let(:product) { create(:product, organization:, billable_metric:) }
    let(:rate_card) { create(:rate_card, :advance, organization:, product:) }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:,
        effective_date: timestamp.to_date, billing_anchor_date: timestamp.to_date)
    end
    let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: timestamp.beginning_of_day) }
    let(:event) do
      build(
        :common_event,
        organization_id: organization.id,
        code: billable_metric.code,
        external_subscription_id: contract.external_id,
        timestamp:
      )
    end

    before do
      contract_rate_card
      rate
    end

    it "returns a schedule-derived segment with its contract context and boundaries" do
      selection = selections.sole

      expect(selection.billing_context.contract).to eq(contract)
      expect(selection.metered_item.billing_segment).to be_new_record
      expect(selection.metered_item).to have_attributes(contract_rate_card:, rate_card_rate: rate, event:)
      expect(selection.metered_item.boundaries).to have_attributes(
        charges_from_datetime: timestamp.beginning_of_day,
        charges_to_datetime: BillingSegment.inclusive_end(timestamp.beginning_of_day + 1.month)
      )
    end
  end

  context "when a subscription and a contract share the external id" do
    let(:organization) { create(:organization, feature_flags:) }
    let(:feature_flags) { [] }
    let(:subscription) { create(:subscription, organization:, customer:, started_at: timestamp - 1.month) }
    let(:charge) { create(:standard_charge, :pay_in_advance, plan: subscription.plan, billable_metric:) }
    let(:contract) { create(:contract, organization:, customer:, external_id: subscription.external_id) }
    let(:product) { create(:product, organization:, billable_metric:) }
    let(:rate_card) { create(:rate_card, :advance, organization:, product:) }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:,
        effective_date: timestamp.to_date, billing_anchor_date: timestamp.to_date)
    end
    let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: timestamp.beginning_of_day) }
    let(:event) do
      build(
        :common_event,
        organization_id: organization.id,
        code: billable_metric.code,
        external_subscription_id: subscription.external_id,
        timestamp:
      )
    end

    before do
      charge
      contract_rate_card
      rate
    end

    it "returns only the charge selection" do
      expect(selections.sole.metered_item.charge).to eq(charge)
    end

    context "when the product catalog is enabled" do
      let(:feature_flags) { [:product_catalog] }

      it "returns only the billing segment selection" do
        expect(selections.sole.metered_item).to have_attributes(contract_rate_card:, rate_card_rate: rate)
      end
    end
  end
end
