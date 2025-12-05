# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilterService do
  subject(:filter_service) { described_class.new(subscription:, boundaries:) }

  let(:organization) { create(:organization) }

  let(:subscription) do
    create(
      :subscription,
      organization:,
      plan:,
      started_at:,
      subscription_at: started_at,
      external_id: "sub_id"
    )
  end

  let(:started_at) { Time.zone.parse("2022-01-01 00:01") }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: Time.zone.parse("2022-03-01 00:00:00"),
      to_datetime: Time.zone.parse("2022-03-31 23:59:59"),
      charges_from_datetime: Time.zone.parse("2022-03-01 00:00:00"),
      charges_to_datetime: Time.zone.parse("2022-03-31 23:59:59"),
      charges_duration: 31.days,
      timestamp: Time.zone.parse("2022-04-02 00:00").end_of_month.to_i
    )
  end

  before { charge }

  describe "#call" do
    it "returns the filtered charge_ids" do
      result = filter_service.call

      expect(result).to be_success
      expect(result.charge_ids).to eq([])
    end

    context "with events matching the boundaries" do
      before do
        create(
          :event,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          timestamp: boundaries.charges_from_datetime + 5.days,
          code: billable_metric.code
        )

        create(
          :event,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          timestamp: boundaries.charges_from_datetime + 5.days,
          code: billable_metric.code
        )
      end

      it "returns filtered charge_ids" do
        result = filter_service.call

        expect(result).to be_success
        expect(result.charge_ids).to eq([charge.id])
      end

      context "with multiple charges for the same billable_metric" do
        let(:charge_2) { create(:standard_charge, plan:, billable_metric:) }

        before { charge_2 }

        it "returns filtered charge_ids" do
          result = filter_service.call

          expect(result).to be_success
          expect(result.charge_ids).to match_array([charge.id, charge_2.id])
        end
      end

      context "with multiple billable metrics" do
        let(:billable_metric_2) { create(:billable_metric, organization:) }
        let(:charge_2) { create(:standard_charge, plan:, billable_metric: billable_metric_2) }

        before do
          charge_2

          create(
            :event,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            timestamp: boundaries.charges_from_datetime + 10.days,
            code: billable_metric_2.code
          )
        end

        it "returns charge_ids for all billable metrics with matching events" do
          result = filter_service.call

          expect(result).to be_success
          expect(result.charge_ids).to match_array([charge.id, charge_2.id])
        end
      end
    end

    context "with recurring billable metric" do
      let(:recurring_billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
      let(:recurring_charge) { create(:standard_charge, plan:, billable_metric: recurring_billable_metric) }

      before { recurring_charge }

      it "returns recurring charge_ids even without events" do
        result = filter_service.call

        expect(result).to be_success
        expect(result.charge_ids).to eq([recurring_charge.id])
      end
    end

    context "with events that does not match the boundaries" do
      before do
        create(
          :event,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          timestamp: boundaries.charges_from_datetime - 5.days,
          code: billable_metric.code
        )
      end

      it "returns filtered charge_ids" do
        result = filter_service.call

        expect(result).to be_success
        expect(result.charge_ids).to eq([])
      end
    end

    context "with unknown event codes" do
      before do
        create(
          :event,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          timestamp: boundaries.charges_from_datetime + 5.days,
          code: "unknown_code"
        )
      end

      it "returns filtered charge_ids" do
        result = filter_service.call

        expect(result).to be_success
        expect(result.charge_ids).to eq([])
      end
    end
  end
end
