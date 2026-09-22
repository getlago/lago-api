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

  context "with a contract billing segment" do
    let(:organization) { create(:organization, feature_flags: [:product_catalog]) }
    let(:contract) { create(:contract, organization:, customer:) }
    let(:product) { create(:product, organization:, billable_metric:) }
    let(:rate_card) { create(:rate_card, :advance, organization:, product:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
    let(:billing_segment) do
      create(
        :billing_segment,
        organization:,
        customer:,
        contract:,
        contract_rate_card:,
        status: :processing,
        cycle_started_at: timestamp.beginning_of_day,
        started_at: timestamp.beginning_of_day,
        ended_at: timestamp.end_of_day
      )
    end
    let(:event) do
      build(
        :common_event,
        organization_id: organization.id,
        code: billable_metric.code,
        external_subscription_id: contract.external_id,
        timestamp:
      )
    end

    before { billing_segment }

    it "returns the billing segment with its contract context and boundaries" do
      selection = selections.sole

      expect(selection.billing_context.contract).to eq(contract)
      expect(selection.metered_item).to have_attributes(billing_segment:, event:)
      expect(selection.metered_item.boundaries).to have_attributes(
        charges_from_datetime: billing_segment.started_at,
        charges_to_datetime: billing_segment.ended_at
      )
    end
  end
end
