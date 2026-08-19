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

  describe "DELETE /api/v2/subscriptions/:external_id" do
    subject { delete_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}", params) }

    let(:params) { {terminated_at:} }
    let(:terminated_at) { "2026-08-14T12:34:56Z" }
    let(:termination_result) do
      V2::Subscriptions::TerminateService::Result.new.tap do |result|
        result.subscription_rate_cards = [subscription_rate_card]
        result.credit_notes = []
      end
    end
    let!(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:, customer:) }

    before do
      allow(V2::Subscriptions::TerminateService).to receive(:call).and_return(termination_result)
    end

    include_examples "requires API permission", "subscription", "write"

    it "terminates the active subscription with the requested timestamp" do
      subject

      expect(response).to have_http_status(:success)
      expect(V2::Subscriptions::TerminateService).to have_received(:call).with(
        subscription:,
        terminated_at: Time.zone.parse(terminated_at)
      )
      expect(json[:applied_rate_cards].sole[:lago_id]).to eq(subscription_rate_card.id)
      expect(json[:credit_notes]).to eq([])
    end

    context "without terminated_at" do
      subject do
        travel_to(current_time) do
          delete_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}")
        end
      end

      let(:current_time) { Time.zone.parse("2026-08-18 08:53:07") }

      it "terminates the subscription at the current time" do
        subject

        expect(response).to have_http_status(:success)
        expect(V2::Subscriptions::TerminateService).to have_received(:call).with(
          subscription:,
          terminated_at: current_time
        )
      end
    end

    context "when the subscription does not exist" do
      subject { delete_with_token(organization, "/api/v2/subscriptions/unknown", params) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("subscription")
        expect(V2::Subscriptions::TerminateService).not_to have_received(:call)
      end
    end

    context "with the real termination flow" do
      before do
        allow(V2::Subscriptions::TerminateService).to receive(:call).and_call_original
      end

      context "with a monthly arrears rate card" do
        let(:terminated_at) { "2026-08-17T12:34:56Z" }
        let(:subscription) do
          create(
            :subscription,
            customer:,
            organization:,
            plan:,
            external_id: "sub_monthly_arrears",
            started_at: Time.zone.parse("2026-08-01"),
            activated_at: Time.zone.parse("2026-08-01"),
            subscription_at: Time.zone.parse("2026-08-01")
          )
        end
        let(:product) { create(:product, :fixed, organization:) }
        let(:rate_card) { create(:rate_card, organization:, product:, code: "monthly_arrears", currency: "EUR") }
        let!(:rate) do
          create(
            :rate_card_rate,
            organization:,
            rate_card:,
            code: "monthly_arrears_v1",
            effective_from: Time.zone.parse("2026-01-01"),
            billing_interval_count: 1,
            billing_interval_unit: "month",
            rate_properties: {"amount" => "31.00"}
          )
        end
        let!(:subscription_rate_card) do
          create(
            :subscription_rate_card,
            organization:,
            subscription:,
            customer:,
            rate_card:,
            billing_anchor_date: Date.parse("2026-08-01"),
            started_at: Time.zone.parse("2026-08-01"),
            next_billing_at: Time.zone.parse("2026-09-01")
          )
        end

        it "creates the final pending billing cycle clamped to the termination time" do
          expect { subject }.to change(BillingCycle, :count).by(1)

          expect(response).to have_http_status(:success)
          expect(json[:credit_notes]).to eq([])

          billing_cycle = BillingCycle.sole
          expect(billing_cycle).to have_attributes(
            subscription:,
            subscription_rate_card:,
            rate_card_rate: rate,
            rate_override: nil,
            period_from: Time.zone.parse("2026-08-01"),
            period_to: Time.zone.parse(terminated_at),
            billing_at: Time.zone.parse(terminated_at),
            status: "pending"
          )
          expect(subscription_rate_card.reload).to have_attributes(
            ended_at: Time.zone.parse(terminated_at),
            next_billing_at: Time.zone.parse(terminated_at)
          )
        end
      end

      context "with multiple rates and phased interval overrides" do
        around do |example|
          travel_to(Time.zone.parse("2026-08-19 00:00:00")) { example.run }
        end

        let(:terminated_at) { 1.second.ago.iso8601 }
        let(:subscription) do
          create(
            :subscription,
            customer:,
            organization:,
            plan:,
            external_id: "sub_phased_arrears",
            started_at: Time.zone.parse("2026-08-03"),
            activated_at: Time.zone.parse("2026-08-03"),
            subscription_at: Time.zone.parse("2026-08-03")
          )
        end
        let(:product) { create(:product, :fixed, organization:) }
        let(:rate_card) { create(:rate_card, organization:, product:, code: "phased_arrears", currency: "EUR") }
        let!(:initial_rate) do
          create(
            :rate_card_rate,
            organization:,
            rate_card:,
            code: "phased_v1",
            effective_from: Time.zone.parse("2026-01-01"),
            billing_interval_count: 1,
            billing_interval_unit: "month",
            rate_properties: {"amount" => "90.00"}
          )
        end
        let!(:active_rate) do
          create(
            :rate_card_rate,
            organization:,
            rate_card:,
            code: "phased_v2",
            effective_from: Time.zone.parse("2026-09-01"),
            billing_interval_count: 1,
            billing_interval_unit: "month",
            rate_properties: {"amount" => "120.00"}
          )
        end
        let!(:future_rate) do
          create(
            :rate_card_rate,
            organization:,
            rate_card:,
            code: "phased_v3",
            effective_from: Time.zone.parse("2026-12-01"),
            billing_interval_count: 2,
            billing_interval_unit: "month",
            rate_properties: {"amount" => "250.00"}
          )
        end
        let!(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, rate_card:) }
        let(:intro_override) do
          create(
            :rate_override,
            organization:,
            billing_interval_count: 1,
            billing_interval_unit: "week",
            rate_properties: {"amount" => "19.00"}
          )
        end
        let!(:intro_phase) do
          create(
            :rate_phase,
            organization:,
            plan_rate_card:,
            code: "weekly_intro",
            position: 1,
            billing_interval_cycle_count: 6,
            rate_override: intro_override
          )
        end
        let!(:standard_phase) do
          create(
            :rate_phase,
            organization:,
            plan_rate_card:,
            code: "monthly_standard",
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
            billing_anchor_date: Date.parse("2026-08-03"),
            started_at: Time.zone.parse("2026-08-03"),
            next_billing_at: Time.zone.parse("2026-10-14")
          )
        end

        it "creates the pending billing cycle overlapping the termination time" do
          expect { subject }.to change(BillingCycle, :count).by(1)

          expect(response).to have_http_status(:success)

          billing_cycles = BillingCycle.order(:period_from, :period_to).to_a
          expect(billing_cycles.map { [it.period_from, it.period_to, it.rate_card_rate, it.rate_override] }).to eq(
            [
              [Time.zone.parse("2026-08-17"), Time.zone.parse(terminated_at), initial_rate, intro_override]
            ]
          )

          final_billing_cycle = billing_cycles.last
          expect(final_billing_cycle).to have_attributes(
            rate_card_rate: initial_rate,
            rate_override: intro_override,
            rate_properties: intro_override.rate_properties,
            period_from: Time.zone.parse("2026-08-17"),
            period_to: Time.zone.parse(terminated_at),
            billing_at: Time.zone.parse(terminated_at)
          )
          expect(json[:applied_rate_cards].sole[:lago_id]).to eq(subscription_rate_card.id)
          expect(billing_cycles.map(&:rate_card_rate)).not_to include(active_rate, future_rate)
          expect([intro_phase, standard_phase].map(&:code)).to eq(%w[weekly_intro monthly_standard])
        end
      end

      context "with a billed monthly advance rate card" do
        let(:terminated_at) { "2026-08-17T12:34:56Z" }
        let(:subscription) do
          create(
            :subscription,
            customer:,
            organization:,
            plan:,
            external_id: "sub_monthly_advance",
            started_at: Time.zone.parse("2026-08-01"),
            activated_at: Time.zone.parse("2026-08-01"),
            subscription_at: Time.zone.parse("2026-08-01")
          )
        end
        let(:product) { create(:product, :fixed, organization:) }
        let(:rate_card) { create(:rate_card, :advance, organization:, product:, code: "monthly_advance", currency: "EUR") }
        let!(:rate) do
          create(
            :rate_card_rate,
            organization:,
            rate_card:,
            code: "monthly_advance_v1",
            effective_from: Time.zone.parse("2026-01-01"),
            billing_interval_count: 1,
            billing_interval_unit: "month",
            rate_properties: {"amount" => "31.00"}
          )
        end
        let!(:subscription_rate_card) do
          create(
            :subscription_rate_card,
            organization:,
            subscription:,
            customer:,
            rate_card:,
            billing_anchor_date: Date.parse("2026-08-01"),
            started_at: Time.zone.parse("2026-08-01"),
            next_billing_at: Time.zone.parse("2026-09-01")
          )
        end
        let(:invoice) do
          create(
            :invoice,
            :subscription,
            organization:,
            customer:,
            subscriptions: [subscription],
            status: :finalized,
            currency: "EUR",
            fees_amount_cents: 3_100,
            total_amount_cents: 3_100
          )
        end
        let!(:billing_cycle) do
          create(
            :billing_cycle,
            organization:,
            subscription:,
            customer:,
            subscription_rate_card:,
            rate_card_rate: rate,
            billing_at: Time.zone.parse("2026-08-01"),
            period_from: Time.zone.parse("2026-08-01"),
            period_to: Time.zone.parse("2026-08-31 23:59:59.999999"),
            invoice:,
            status: :done
          )
        end
        let!(:fee) do
          create(
            :fee,
            organization:,
            subscription:,
            invoice:,
            invoiceable: product,
            amount_cents: 3_100,
            precise_amount_cents: 3_100,
            amount_currency: "EUR",
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0
          )
        end
        let(:taxes_result) do
          CreditNotes::ApplyTaxesService::Result.new.tap do |result|
            result.applied_taxes = []
            result.coupons_adjustment_amount_cents = 0
            result.taxes_amount_cents = 0
            result.precise_taxes_amount_cents = 0
            result.taxes_rate = 0
          end
        end

        before do
          allow(CreditNotes::ApplyTaxesService).to receive(:call).and_return(taxes_result)
        end

        it "does not create a final billing cycle and credits the unused period" do
          expect { subject }
            .to change(CreditNote, :count).by(1)
            .and change(CreditNoteItem, :count).by(1)
            .and not_change(BillingCycle, :count)

          expect(response).to have_http_status(:success)

          credit_note = CreditNote.sole
          credit_note_item = CreditNoteItem.sole
          expect(credit_note).to have_attributes(
            invoice:,
            reason: "order_cancellation",
            credit_amount_cents: credit_note_item.amount_cents,
            total_amount_cents: credit_note_item.amount_cents,
            status: "finalized"
          )
          expect(credit_note_item.fee).to eq(fee)
          expect(credit_note_item.amount_cents).to be_positive
          expect(credit_note_item.amount_cents).to be < fee.amount_cents
          expect(json[:credit_notes].sole[:lago_id]).to eq(credit_note.id)
          expect(subscription_rate_card.reload).to have_attributes(
            ended_at: Time.zone.parse(terminated_at),
            next_billing_at: Time.zone.parse("2026-09-01")
          )
          expect(billing_cycle.reload).to be_done
        end
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
        end_on: "2026-08-14"
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
          end_on: "2026-08-14"
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
          end_on: '"2026-09-10"'
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
          end_on: "hello"
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
            end_on: "2026-09-10"
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

      let!(:subscription_rate_card) do
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
        expect(subscription_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-10"))
      end

      it "returns a validation error when billing the same period twice" do
        subject
        expect(response).to have_http_status(:success)

        # Put back the clock to the already-billed period, as if the item were due
        # for it again (e.g. a clock re-run), so the second attempt collides with
        # the billing cycle created above instead of scheduling the next period.
        subscription_rate_card.reload.update!(next_billing_at: Time.zone.parse("2026-08-10"))

        expect do
          post_with_token(
            organization,
            "/api/v2/subscriptions/bill",
            {
              subscription_external_ids: ["sub_r1"],
              end_on: "2026-09-10"
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
        effective_from: rate_effective_from
      )
    end
    let(:rate_effective_from) { Time.zone.parse("2026-01-01") }
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
            cycle_index: 1,
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
            cycle_index: 2,
            period_from: Time.zone.parse("2026-09-10").iso8601,
            period_to: Time.zone.parse("2026-10-09 23:59:59").iso8601,
            billing_at: Time.zone.parse("2026-09-15").iso8601,
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

    context "when no rate is available in the requested range" do
      subject do
        travel_to(Time.zone.parse("2026-08-10")) do
          get_with_token(
            organization,
            "/api/v2/subscriptions/cycles",
            {
              subscription_external_ids: [subscription.external_id],
              start_on: "2026-08-10",
              end_on: "2026-09-10"
            }
          )
        end
      end

      let(:rate_card) { create(:rate_card, organization:, product:, code: "card_r2", currency: "USD") }
      let(:rate_effective_from) { Time.zone.parse("2027-01-01") }

      it "does not return a next billing date" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:cycles]).to eq([])
        expect(json).not_to have_key(:next_billing_at)
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
        expect(json[:cycles].map { |cycle| cycle[:cycle_index] }).to eq([1, 2])
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
        expect(json[:cycles].map { |cycle| cycle[:cycle_index] }).to eq([1])
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

        period = json[:cycles].find { |cycle| cycle[:cycle_index] == 7 }
        expect(period[:period_from]).to eq(Time.zone.parse("2026-09-21").iso8601)
        expect(period[:period_to]).to eq(Time.zone.parse("2026-10-20").end_of_day.iso8601)
      end
    end
  end
end
