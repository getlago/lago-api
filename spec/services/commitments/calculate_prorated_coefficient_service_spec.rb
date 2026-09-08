# frozen_string_literal: true

require "rails_helper"

RSpec.describe Commitments::CalculateProratedCoefficientService do
  let(:service) { described_class.new(commitment:, invoice_subscription:) }
  let(:commitment) { create(:commitment, plan:) }
  let(:plan) { create(:plan, organization:) }
  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, customer:, plan:, started_at:) }
  let(:customer) { create(:customer, organization:) }

  let(:invoice_subscription) do
    create(
      :invoice_subscription,
      subscription:,
      from_datetime:,
      to_datetime:,
      charges_from_datetime:,
      charges_to_datetime:,
      timestamp:
    )
  end

  let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
  let(:started_at) { DateTime.parse("2024-01-01T00:00:00") }
  let(:to_datetime) { DateTime.parse("2024-01-31T23:59:59") }
  let(:charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
  let(:charges_to_datetime) { DateTime.parse("2024-01-31T23:59:59") }
  let(:timestamp) { DateTime.parse("2024-02-01T10:00:00") }

  describe "#proration_coefficient" do
    subject(:apply_service) { service.proration_coefficient }

    context "with whole period" do
      it "returns proration coefficient" do
        expect(apply_service.proration_coefficient).to eq(1.0)
      end
    end

    context "with partial period" do
      let(:from_datetime) { DateTime.parse("2024-01-15T00:00:00") }

      it "returns proration coefficient" do
        expect(apply_service.proration_coefficient).to eq(0.5483870967741935)
      end
    end

    context "when subscription is terminated" do
      let(:from_datetime) { DateTime.current.beginning_of_day }
      let(:started_at) { DateTime.current }
      let(:to_datetime) { nil }
      let(:days_in_month) { Date.current.end_of_month.day }

      before do
        Subscriptions::TerminateService.call(subscription:, async: false)
      end

      it "returns proration coefficient" do
        invoice_subscription = subscription.invoice_subscriptions.reload.last
        apply_service = described_class.new(commitment:, invoice_subscription:).proration_coefficient

        expect(apply_service.proration_coefficient).to eq(1 / days_in_month.to_f)
      end
    end

    context "when subscription is downgraded right after the period ended" do
      let(:started_at) { DateTime.parse("2024-01-01T00:00:00") }
      let(:from_datetime) { DateTime.parse("2024-07-01T00:00:00") }
      let(:to_datetime) { DateTime.parse("2024-07-31T23:59:59") }
      let(:charges_from_datetime) { from_datetime }
      let(:charges_to_datetime) { to_datetime }
      let(:terminated_at) { DateTime.parse("2024-08-01T00:15:49") }
      let(:timestamp) { terminated_at }

      let(:cheaper_plan) { create(:plan, organization:, amount_cents: plan.amount_cents / 2) }

      before do
        create(:subscription, :pending, customer:, plan: cheaper_plan, previous_subscription: subscription)
        subscription.update!(status: :terminated, terminated_at:)
      end

      it "returns the coefficient of the whole period that was billed" do
        expect(apply_service.proration_coefficient).to eq(1.0)
      end
    end
  end
end
