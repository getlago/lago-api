# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::PayInAdvanceBillingSegmentResolver do
  subject(:billing_segments) { described_class.call!(event:).billing_segments }

  let(:organization) { create(:organization, feature_flags: [:product_catalog]) }
  let(:customer) { create(:customer, organization:) }
  let(:timestamp) { Time.current - 1.second }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:contract_status) { :active }
  let(:contract_ended_at) { nil }
  let(:contract) do
    create(
      :contract,
      organization:,
      customer:,
      status: contract_status,
      ended_at: contract_ended_at
    )
  end
  let(:event_external_subscription_id) { contract.external_id }
  let(:event) do
    Events::Common.new(
      organization_id: organization.id,
      external_subscription_id: event_external_subscription_id,
      timestamp:,
      code: billable_metric.code,
      properties: {}
    )
  end
  let(:product_billable_metric) { billable_metric }
  let(:product) { create(:product, :metered, organization:, billable_metric: product_billable_metric) }
  let(:billing_timing) { :advance }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:segment_status) { :processing }
  let(:segment_started_at) { timestamp.beginning_of_day }
  let(:segment_ended_at) { timestamp.end_of_day }
  let(:billing_segment) do
    create(
      :billing_segment,
      organization:,
      customer:,
      contract:,
      contract_rate_card:,
      cycle_started_at: segment_started_at,
      started_at: segment_started_at,
      ended_at: segment_ended_at,
      status: segment_status
    )
  end

  before { billing_segment }

  context "when the product catalog is disabled" do
    let(:organization) { create(:organization) }

    it "returns no billing segments" do
      expect(billing_segments).to be_empty
    end
  end

  it "returns a processing segment for an active contract and advance rate card" do
    expect(billing_segments).to contain_exactly(billing_segment)
  end

  context "when the contract is pending" do
    let(:contract_status) { :pending }

    it "returns the billing segment" do
      expect(billing_segments).to contain_exactly(billing_segment)
    end
  end

  context "when the contract is terminated" do
    let(:contract_status) { :terminated }

    it "does not return the billing segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "when the contract is canceled" do
    let(:contract_status) { :canceled }

    it "does not return the billing segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "with a terminated and a live contract sharing the external id" do
    let(:contract_status) { :terminated }
    let(:contract_ended_at) { timestamp - 1.second }
    let(:live_contract) { create(:contract, organization:, customer:, external_id: contract.external_id, status: :active) }
    let(:live_contract_rate_card) { create(:contract_rate_card, organization:, contract: live_contract, rate_card:) }
    let(:live_billing_segment) do
      create(
        :billing_segment,
        organization:,
        customer:,
        contract: live_contract,
        contract_rate_card: live_contract_rate_card,
        rate_card_rate: billing_segment.rate_card_rate,
        started_at: segment_started_at,
        ended_at: segment_ended_at,
        status: segment_status
      )
    end

    before { live_billing_segment }

    it "returns only the live contract billing segment" do
      expect(billing_segments).to contain_exactly(live_billing_segment)
    end
  end

  context "when the contract ended before the event" do
    let(:contract_ended_at) { timestamp - 1.second }

    it "returns the billing segment" do
      expect(billing_segments).to contain_exactly(billing_segment)
    end
  end

  context "when the event external subscription id does not match the contract" do
    let(:event_external_subscription_id) { SecureRandom.uuid }

    it "does not return the billing segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "when the segment is not processing" do
    let(:segment_status) { :pending }

    it "does not return the billing segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "when the event is outside the billing segment period" do
    let(:segment_ended_at) { timestamp - 1.second }

    it "does not return the billing segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "with adjacent rate segments" do
    let(:boundary_at) { Time.zone.parse("2027-01-15 12:00:00") }
    let(:segment_started_at) { Time.zone.parse("2027-01-01 00:00:00") }
    let(:segment_ended_at) { BillingSegment.inclusive_end(boundary_at) }
    let(:next_cycle_started_at) { segment_started_at }
    let(:next_segment) do
      create(:billing_segment, organization:, customer:, contract:, contract_rate_card:,
        rate_card_rate: billing_segment.rate_card_rate,
        cycle_started_at: next_cycle_started_at, started_at: boundary_at,
        ended_at: BillingSegment.inclusive_end(boundary_at + 1.day), status: :processing)
    end

    before { next_segment }

    context "when the event falls in the last millisecond before the rate change" do
      let(:timestamp) { boundary_at - Rational(500, 1_000_000) }

      it "selects the previous segment" do
        expect(billing_segments).to contain_exactly(billing_segment)
      end
    end

    context "when the event occurs at the rate change" do
      let(:timestamp) { boundary_at }

      it "selects the next segment only" do
        expect(billing_segments).to contain_exactly(next_segment)
      end
    end

    context "when the rate change is at the beginning of a new cycle" do
      let(:boundary_at) { Time.zone.parse("2027-02-01 00:00:00") }
      let(:next_cycle_started_at) { boundary_at }

      context "when the event has millisecond precision before the new cycle" do
        let(:timestamp) { boundary_at - Rational(1, 1000) }

        it "selects the old cycle" do
          expect(billing_segments).to contain_exactly(billing_segment)
        end
      end

      context "when the event occurs at the last microsecond of the old cycle" do
        let(:timestamp) { boundary_at - BillingSegment::MICROSECOND }

        it "selects the old cycle" do
          expect(billing_segments).to contain_exactly(billing_segment)
        end
      end

      context "when the event has submicrosecond precision before the new cycle" do
        let(:timestamp) { boundary_at - Rational(1, 2_000_000) }

        it "selects the old cycle using the database's microsecond precision" do
          expect(billing_segments).to contain_exactly(billing_segment)
        end
      end

      context "when the event occurs at the start of the new cycle" do
        let(:timestamp) { boundary_at }

        it "selects the new cycle" do
          expect(billing_segments).to contain_exactly(next_segment)
        end
      end
    end

    context "when the new segment starts between milliseconds" do
      let(:boundary_at) { Time.zone.parse("2027-01-15 12:00:00.123456") }

      context "when the event occurs before the start" do
        let(:timestamp) { Time.zone.parse("2027-01-15 12:00:00.123000") }

        it "does not select the new segment early" do
          expect(billing_segments).to contain_exactly(billing_segment)
        end
      end

      context "when the event occurs just before the start" do
        let(:timestamp) { boundary_at - BillingSegment::MICROSECOND }

        it "selects the previous segment" do
          expect(billing_segments).to contain_exactly(billing_segment)
        end
      end
    end
  end

  context "when the rate card bills in arrears" do
    let(:billing_timing) { :arrears }

    it "does not return the billing segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "when the product has a different billable metric" do
    let(:product_billable_metric) { create(:billable_metric, organization:) }

    it "does not return the billing segment" do
      expect(billing_segments).to be_empty
    end
  end
end
