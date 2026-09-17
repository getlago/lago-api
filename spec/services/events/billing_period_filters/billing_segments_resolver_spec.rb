# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilters::BillingSegmentsResolver do
  subject(:filter_targets) { resolver.filter_targets }

  let(:resolver) { described_class.new(billing_segments: [billing_segment]) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:, external_id: "contract-id") }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:rate_card) { create(:rate_card, organization:, product:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
  let(:billing_segment) do
    create(
      :billing_segment,
      organization:,
      customer:,
      contract:,
      contract_rate_card:,
      rate_card_rate:,
      cycle_started_at: Time.zone.parse("2026-09-01"),
      started_at: Time.zone.parse("2026-09-01"),
      ended_at: Time.zone.parse("2026-09-30 23:59:59")
    )
  end

  describe "#filter_targets" do
    it "memoizes the filter target for a billing segment instance" do
      create(
        :event,
        organization:,
        customer:,
        external_subscription_id: contract.external_id,
        code: billable_metric.code,
        timestamp: billing_segment.started_at + 1.day
      )
      allow(Events::BillingPeriodFilters::FilterTarget).to receive(:from_billing_segment).and_call_original

      filter_targets

      expect(Events::BillingPeriodFilters::FilterTarget).to have_received(:from_billing_segment).once
    end
  end
end
