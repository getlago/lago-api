# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilters::ChargesResolver do
  subject(:filter_targets) { resolver.filter_targets }

  let(:resolver) { described_class.new(subscription:, boundaries:) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) do
    create(:subscription, organization:, customer:, plan:, external_id: "subscription-id")
  end
  let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:billable_metric_filter) do
    create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us])
  end
  let(:charge_filter) { create(:charge_filter, charge:) }
  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: Time.zone.parse("2026-09-01"),
      to_datetime: Time.zone.parse("2026-09-30 23:59:59"),
      charges_from_datetime: Time.zone.parse("2026-09-01"),
      charges_to_datetime: Time.zone.parse("2026-09-30 23:59:59"),
      charges_duration: 30.days,
      timestamp: Time.zone.parse("2026-09-30 23:59:59").to_i
    )
  end

  describe "#filter_targets" do
    it "memoizes filter targets by charge instance rather than charge id" do
      create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
      create(
        :event,
        organization:,
        customer:,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: boundaries.charges_from_datetime + 1.day,
        properties: {"region" => "eu"}
      )

      target_charges = []
      allow(Events::BillingPeriodFilters::FilterTarget).to receive(:from_charge).and_wrap_original do |method, charge:, filter: nil|
        target_charges << charge
        method.call(charge:, filter:)
      end

      filter_targets

      expect(target_charges.map(&:id)).to eq([charge.id, charge.id])
      expect(target_charges.map(&:object_id).uniq.size).to eq(2)
    end
  end
end
