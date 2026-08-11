# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::SubscriptionsController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }
  let(:subscription) { create(:subscription, customer:, plan:, organization:) }

  describe "GET /api/v2/subscriptions" do
    subject { get_with_token(organization, "/api/v2/subscriptions") }

    before do
      create(:subscription_rate_card, organization:, subscription:)
      # An ended version must not inflate the grouped count.
      create(:subscription_rate_card, organization:, subscription:, started_at: 10.days.ago, ended_at: 1.day.ago)
    end

    include_examples "requires API permission", "subscription", "read"

    it "returns subscriptions in the v2 shape" do
      subject

      expect(response).to have_http_status(:success)

      result = json[:subscriptions].sole
      expect(result[:lago_id]).to eq(subscription.id)
      expect(result[:plan_code]).to eq(plan.code)
      expect(result[:applied_rate_cards_count]).to eq(1)
      expect(result).not_to have_key(:current_billing_period_started_at)
      expect(result).not_to have_key(:plan_amount_cents)
    end

    context "with a pending subscription" do
      let!(:pending_subscription) { create(:subscription, :pending, customer:, plan:, organization:) }

      it "lists only active subscriptions by default" do
        subject

        expect(json[:subscriptions].map { |s| s[:lago_id] }).to eq([subscription.id])
      end

      it "lists pending subscriptions when the status filter asks for them" do
        get_with_token(organization, "/api/v2/subscriptions?status[]=pending")

        expect(json[:subscriptions].map { |s| s[:lago_id] }).to eq([pending_subscription.id])
      end
    end
  end

  describe "GET /api/v2/subscriptions/:external_id" do
    subject { get_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}") }

    let!(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:) }

    include_examples "requires API permission", "subscription", "read"

    it "returns the subscription with its rate card entries" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscription][:lago_id]).to eq(subscription.id)
      expect(json[:subscription][:applied_rate_cards].sole[:lago_id]).to eq(subscription_rate_card.id)
    end

    context "with an ended version of an entry" do
      before do
        create(:subscription_rate_card, organization:, subscription:, started_at: 10.days.ago, ended_at: 1.day.ago)
      end

      it "excludes it from the count and the list" do
        subject

        expect(json[:subscription][:applied_rate_cards_count]).to eq(1)
        expect(json[:subscription][:applied_rate_cards].sole[:lago_id]).to eq(subscription_rate_card.id)
      end
    end

    context "when the external id contains a dot" do
      let(:subscription) { create(:subscription, customer:, plan:, organization:, external_id: "sub.2026-01") }

      it "matches the full id instead of truncating at the format separator" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscription][:external_id]).to eq("sub.2026-01")
      end
    end

    context "when it does not exist" do
      subject { get_with_token(organization, "/api/v2/subscriptions/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("subscription")
      end
    end
  end

  describe "POST /api/v2/subscriptions/:external_id/bill" do
    subject do
      post_with_token(
        organization,
        "/api/v2/subscriptions/#{subscription.external_id}/bill",
        {start_on: "2026-08-01", end_on: "2026-08-14"}
      )
    end

    let(:billing_result) do
      V2::Subscriptions::BillService::Result.new.tap do |result|
        result.invoices = []
        result.credit_notes = []
      end
    end

    before do
      allow(V2::Subscriptions::BillService).to receive(:call).and_return(billing_result)
    end

    it "passes the requested range to the bill service" do
      subject

      expect(response).to have_http_status(:success)
      expect(V2::Subscriptions::BillService).to have_received(:call).with(
        subscriptions: [subscription],
        start_on: "2026-08-01",
        end_on: "2026-08-14",
        terminate: false
      )
    end

    context "without start_on" do
      subject do
        post_with_token(
          organization,
          "/api/v2/subscriptions/#{subscription.external_id}/bill",
          {end_on: "2026-08-14"}
        )
      end

      it "uses end_on as the range start" do
        subject

        expect(response).to have_http_status(:success)
        expect(V2::Subscriptions::BillService).to have_received(:call).with(
          subscriptions: [subscription],
          start_on: nil,
          end_on: "2026-08-14",
          terminate: false
        )
      end
    end

    context "with a quoted date param" do
      subject do
        post_with_token(
          organization,
          "/api/v2/subscriptions/#{subscription.external_id}/bill",
          {end_on: '"2026-09-10"'}
        )
      end

      it "removes extra quotes before building the range" do
        subject

        expect(response).to have_http_status(:success)
        expect(V2::Subscriptions::BillService).to have_received(:call).with(
          subscriptions: [subscription],
          start_on: nil,
          end_on: '"2026-09-10"',
          terminate: false
        )
      end
    end

    context "with an invalid date param" do
      subject do
        post_with_token(
          organization,
          "/api/v2/subscriptions/#{subscription.external_id}/bill",
          {end_on: "hello"}
        )
      end

      it "passes the invalid range to the bill service" do
        subject

        expect(response).to have_http_status(:success)
        expect(V2::Subscriptions::BillService).to have_received(:call).with(
          subscriptions: [subscription],
          start_on: nil,
          end_on: "hello",
          terminate: false
        )
      end
    end

    context "with the QA billing run payload" do
      subject do
        post_with_token(
          organization,
          "/api/v2/subscriptions/bill",
          {
            subscription_external_ids: ["sub_r1"],
            end_on: "2026-09-10",
            terminate: false
          }
        )
      end

      let(:subscription) do
        create(
          :subscription,
          organization:,
          customer:,
          plan:,
          external_id: "sub_r1",
          started_at: Time.zone.parse("2026-08-10"),
          activated_at: Time.zone.parse("2026-08-10"),
          subscription_at: Time.zone.parse("2026-08-10")
        )
      end
      let(:product) { create(:product, :fixed, organization:) }
      let(:rate_card) { create(:rate_card, organization:, product:, code: "card_r1", currency: "USD") }
      let!(:rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          code: "rate_r1_v1",
          effective_from: Time.zone.parse("2026-01-01"),
          rate_properties: {"amount" => "30.00"}
        )
      end

      before do
        allow(V2::Subscriptions::BillService).to receive(:call).and_call_original
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          code: "rate_r1_v2",
          effective_from: Time.zone.parse("2026-12-01"),
          rate_properties: {"amount" => "40.00"}
        )
        create(
          :subscription_rate_card,
          organization:,
          subscription:,
          customer:,
          rate_card:,
          units: 5,
          billing_anchor_date: Date.parse("2026-08-10"),
          started_at: Time.zone.parse("2026-08-10"),
          next_billing_at: Time.zone.parse("2026-08-10")
        )
      end

      it "creates one billing cycle for the latest period using the active rate" do
        expect { subject }.to change(BillingCycle, :count).by(1)

        expect(response).to have_http_status(:success)

        billing_cycle = BillingCycle.sole
        fee = Fee.sole
        expect(billing_cycle.period_from).to eq(Time.zone.parse("2026-08-10"))
        expect(billing_cycle.period_to).to eq(Time.zone.parse("2026-09-09 23:59:59.999999"))
        expect(fee.rate_card_rate).to eq(rate)
        expect(fee.amount_cents).to eq(15_000)
        expect(json[:invoices].sole[:fees].sole[:lago_id]).to eq(fee.id)
      end

      it "returns a validation error when billing the same period twice" do
        subject
        expect(response).to have_http_status(:success)

        expect do
          post_with_token(
            organization,
            "/api/v2/subscriptions/bill",
            {
              subscription_external_ids: ["sub_r1"],
              end_on: "2026-09-10",
              terminate: false
            }
          )
        end.not_to change(BillingCycle, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(billing_cycle: ["overlapping_periods"])
      end
    end
  end

  describe "GET /api/v2/subscriptions/:external_id/cycles" do
    subject do
      travel_to(Time.zone.parse("2026-09-15")) do
        get_with_token(
          organization,
          "/api/v2/subscriptions/#{subscription.external_id}/cycles",
          {end_on: "2026-10-09"}
        )
      end
    end

    let(:subscription) do
      create(
        :subscription,
        organization:,
        customer:,
        plan:,
        external_id: "sub_r1",
        started_at: Time.zone.parse("2026-08-10"),
        activated_at: Time.zone.parse("2026-08-10"),
        subscription_at: Time.zone.parse("2026-08-10")
      )
    end
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, code: "card_r1", currency: "USD") }
    let(:rate_override) { create(:rate_override, organization:, rate_properties: {"amount" => "49.00"}) }
    let!(:rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        code: "rate_r1_v1",
        effective_from: Time.zone.parse("2026-01-01")
      )
    end
    let!(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, rate_card:) }
    let!(:intro_phase) do
      create(
        :rate_phase,
        organization:,
        plan_rate_card:,
        code: "negotiated_intro",
        position: 1,
        billing_interval_cycle_count: 1,
        rate_override:
      )
    end
    let!(:standard_phase) do
      create(
        :rate_phase,
        organization:,
        plan_rate_card:,
        code: "standard",
        position: 2,
        billing_interval_cycle_count: nil
      )
    end

    let!(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        subscription:,
        customer:,
        rate_card:,
        billing_anchor_date: Date.parse("2026-08-10"),
        started_at: Time.zone.parse("2026-08-10"),
        next_billing_at: Time.zone.parse("2026-08-10")
      )
    end

    include_examples "requires API permission", "subscription", "read"

    it "returns full periods generated by the dates service" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:next_billing_at]).to eq(Time.zone.parse("2026-10-10").iso8601)
      expect(json[:cycles]).to eq(
        [
          {
            subscription_external_id: subscription.external_id,
            subscription_started_at: subscription.started_at.iso8601,
            applied_rate_card_id: subscription_rate_card.id,
            applied_rate_card_code: rate_card.code,
            cycle_index: 0,
            period_from: Time.zone.parse("2026-08-10").iso8601,
            period_to: Time.zone.parse("2026-09-09 23:59:59").iso8601,
            billing_at: Time.zone.parse("2026-09-15").iso8601,
            rate_phase_code: intro_phase.code,
            rate_override: {
              lago_id: rate_override.id,
              rate_model: rate_override.rate_model,
              rate_properties: rate_override.rate_properties.symbolize_keys,
              billing_interval_count: rate_override.billing_interval_count,
              billing_interval_unit: rate_override.billing_interval_unit
            },
            rate: nil,
            rate_code: rate.code
          },
          {
            subscription_external_id: subscription.external_id,
            subscription_started_at: subscription.started_at.iso8601,
            applied_rate_card_id: subscription_rate_card.id,
            applied_rate_card_code: rate_card.code,
            cycle_index: 1,
            period_from: Time.zone.parse("2026-09-10").iso8601,
            period_to: Time.zone.parse("2026-10-09 23:59:59").iso8601,
            billing_at: Time.zone.parse("2026-10-09 23:59:59").iso8601,
            rate_phase_code: standard_phase.code,
            rate_override: nil,
            rate: {
              lago_id: rate.id,
              code: rate.code,
              rate_model: rate.rate_model,
              rate_properties: rate.rate_properties.symbolize_keys,
              billing_interval_count: rate.billing_interval_count,
              billing_interval_unit: rate.billing_interval_unit
            },
            rate_code: rate.code
          }
        ]
      )
    end

    context "with subscription_external_ids" do
      subject do
        travel_to(Time.zone.parse("2026-09-15")) do
          get_with_token(
            organization,
            "/api/v2/subscriptions/cycles",
            {subscription_external_ids: [subscription.external_id], end_on: "2026-10-09"}
          )
        end
      end

      it "accepts the same identifier payload as bill" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:cycles].map { |cycle| cycle[:subscription_external_id] })
          .to eq([subscription.external_id] * 2)
      end
    end

    context "with a pending subscription and an explicit start_on" do
      subject do
        travel_to(Time.zone.parse("2026-08-11")) do
          get_with_token(
            organization,
            "/api/v2/subscriptions/cycles",
            {
              subscription_external_ids: subscription.external_id,
              start_on: "2026-08-01",
              end_on: "2026-11-30"
            }
          )
        end
      end

      let(:subscription) do
        create(
          :subscription,
          :pending,
          organization:,
          customer:,
          plan:,
          external_id: "s_cs1cA_5"
        )
      end
      let(:rate_card) { create(:rate_card, organization:, product:, code: "card_r1", currency: "USD") }
      let(:subscription_rate_card) do
        create(
          :subscription_rate_card,
          organization:,
          subscription:,
          customer:,
          rate_card:,
          billing_anchor_date: Date.parse("2026-09-01"),
          started_at: Time.zone.parse("2026-09-01"),
          next_billing_at: Time.zone.parse("2026-10-01")
        )
      end

      it "uses the requested range start without requiring the subscription to be started" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:cycles].first[:subscription_started_at]).to be_nil
        expect(json[:cycles].first[:period_from]).to eq(Time.zone.parse("2026-09-01").iso8601)
      end
    end

    context "without end_on" do
      subject do
        travel_to(Time.zone.parse("2026-09-15")) do
          get_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/cycles")
        end
      end

      it "uses the current time as the range end" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:cycles].map { |cycle| cycle[:cycle_index] }).to eq([0, 1])
        expect(json[:cycles].last[:period_to]).to eq(Time.zone.parse("2026-10-09 23:59:59").iso8601)
      end
    end

    context "when end_on falls inside an advance cycle" do
      subject do
        travel_to(Time.zone.parse("2026-08-11")) do
          get_with_token(
            organization,
            "/api/v2/subscriptions/#{subscription.external_id}/cycles",
            {end_on: "2026-08-11"}
          )
        end
      end

      it "returns the full cycle instead of clipping it to the requested range" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:cycles].map { |cycle| cycle[:cycle_index] }).to eq([0])
        expect(json[:cycles].sole[:period_from]).to eq(Time.zone.parse("2026-08-10").iso8601)
        expect(json[:cycles].sole[:period_to]).to eq(Time.zone.parse("2026-09-09 23:59:59").iso8601)
      end
    end

    context "with realign_billing_anchor" do
      subject do
        get_with_token(
          organization,
          "/api/v2/subscriptions/#{subscription.external_id}/cycles",
          {end_on: "2026-10-31"}
        )
      end

      before do
        intro_phase.update!(
          billing_interval_cycle_count: 6,
          rate_override: create(
            :rate_override,
            organization:,
            billing_interval_count: 1,
            billing_interval_unit: "week",
            rate_properties: {"amount" => "19.00"}
          )
        )
      end

      it "continues the base interval from the weekly override end" do
        subject

        period = json[:cycles].find { |cycle| cycle[:cycle_index] == 6 }
        expect(period[:period_from]).to eq(Time.zone.parse("2026-09-21").iso8601)
        expect(period[:period_to]).to eq(Time.zone.parse("2026-10-20").end_of_day.iso8601)
      end
    end
  end
end
