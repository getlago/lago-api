# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::PostProcessService do
  subject(:process_service) { described_class.new(event:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric:) }

  let(:started_at) { Time.current - 3.days }
  let(:external_subscription_id) { subscription.external_id }
  let(:code) { billable_metric&.code }
  let(:timestamp) { Time.current - 1.second }
  let(:event_properties) { {} }

  let(:event) do
    create(
      :event,
      organization_id: organization.id,
      external_subscription_id:,
      timestamp:,
      code:,
      properties: event_properties
    )
  end

  before do
    charge
    create(:wallet, customer:)
  end

  describe "#call" do
    it "marks customer as awaiting wallet refresh" do
      expect { process_service.call }.to change { customer.reload.awaiting_wallet_refresh }.from(false).to(true)
    end

    it "tracks subscription activity" do
      allow(UsageMonitoring::TrackSubscriptionActivityService).to receive(:call)

      process_service.call

      expected_date = Time.current.in_time_zone(customer.applicable_timezone).to_date
      expect(UsageMonitoring::TrackSubscriptionActivityService).to have_received(:call)
        .with(subscription:, organization:, date: expected_date)
    end

    context "with events enrichment" do
      it "does not create an enriched event" do
        expect { process_service.call }.not_to change(EnrichedEvent, :count)
      end

      context "when the feature flag is enabled" do
        let(:organization) { create(:organization, feature_flags: [:postgres_enriched_events]) }

        it "creates enriched event" do
          expect { process_service.call }.to change(EnrichedEvent, :count).by(1)
        end
      end
    end

    context "when the event is backdated before the subscription started" do
      let(:timestamp) { started_at - 7.days }

      context "with a recurring billable metric" do
        let(:billable_metric) do
          create(:billable_metric, organization:, recurring: true, aggregation_type: "sum_agg", field_name: "item_id")
        end
        let(:event_properties) { {"item_id" => "12"} }

        it "tracks subscription activity on the fallback subscription" do
          allow(UsageMonitoring::TrackSubscriptionActivityService).to receive(:call)

          process_service.call

          expect(UsageMonitoring::TrackSubscriptionActivityService).to have_received(:call)
            .with(subscription:, organization:, date: kind_of(Date))
        end

        it "enqueues a pay in advance job" do
          expect { process_service.call }.to have_enqueued_job(Events::PayInAdvanceJob)
        end
      end

      context "with a non-recurring billable metric" do
        it "does not fall back on the currently active subscription" do
          allow(UsageMonitoring::TrackSubscriptionActivityService).to receive(:call)

          process_service.call

          expect(UsageMonitoring::TrackSubscriptionActivityService).not_to have_received(:call)
        end
      end
    end

    context "when subscription is incomplete" do
      let(:subscription) do
        create(:subscription, :incomplete, organization:, customer:, plan:, started_at:)
      end

      it "does not enqueue a pay in advance job" do
        expect { process_service.call }.not_to have_enqueued_job(Events::PayInAdvanceJob)
      end

      it "does not track subscription activity" do
        allow(UsageMonitoring::TrackSubscriptionActivityService).to receive(:call)

        process_service.call

        expect(UsageMonitoring::TrackSubscriptionActivityService).not_to have_received(:call)
      end
    end

    context "when event matches an pay_in_advance charge" do
      let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric:, invoiceable: false) }
      let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "item_id") }
      let(:event_properties) { {billable_metric.field_name => "12"} }

      before { charge }

      it "enqueues a job to perform the pay_in_advance aggregation" do
        expect { process_service.call }.to have_enqueued_job(Events::PayInAdvanceJob)
      end
    end

    context "when the product catalog is enabled" do
      let(:organization) { create(:organization, feature_flags: [:product_catalog]) }
      let(:customer) { create(:customer, organization:) }
      let(:external_subscription_id) { contract.external_id }
      let(:charge) { nil }
      let(:contract) { create(:contract, organization:, customer:, ended_at:, status: contract_status) }
      let(:contract_status) { :active }
      let(:effective_date) { timestamp.to_date }
      let(:ended_at) { nil }
      let(:product) { create(:product, :metered, organization:, billable_metric:) }
      let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:) }
      let(:billing_timing) { :advance }

      before do
        contract_rate_card = create(:contract_rate_card, organization:, contract:, rate_card:, effective_date:)
        create(:billing_segment, organization:, customer:, contract:, contract_rate_card:,
          started_at: effective_date.beginning_of_day,
          ended_at: effective_date.end_of_day + 1.month,
          status: :collecting)
      end

      context "when the rate card is effective at the event timestamp" do
        let(:effective_date) { timestamp.to_date }

        it "enqueues a pay in advance job" do
          expect { process_service.call }.to have_enqueued_job(Events::PayInAdvanceJob)
        end
      end

      context "when the rate card is scheduled after the event" do
        let(:effective_date) { timestamp.to_date + 1.day }

        it "does not enqueue a pay in advance job" do
          expect { process_service.call }.not_to have_enqueued_job(Events::PayInAdvanceJob)
        end
      end

      context "when the contract has ended" do
        let(:effective_date) { timestamp.to_date }
        let(:ended_at) { timestamp - 1.second }

        it "does not enqueue a pay in advance job" do
          expect { process_service.call }.not_to have_enqueued_job(Events::PayInAdvanceJob)
        end
      end

      context "when the contract ends after the event" do
        let(:effective_date) { timestamp.to_date }
        let(:ended_at) { timestamp + 1.second }

        it "enqueues a pay in advance job" do
          expect { process_service.call }.to have_enqueued_job(Events::PayInAdvanceJob)
        end
      end

      context "when the contract ends at the event timestamp" do
        let(:timestamp) { (Time.current - 1.second).change(usec: 0) }
        let(:effective_date) { timestamp.to_date }
        let(:ended_at) { timestamp }

        it "enqueues a pay in advance job" do
          expect { process_service.call }.to have_enqueued_job(Events::PayInAdvanceJob)
        end
      end

      context "when the contract is terminated" do
        let(:contract_status) { :terminated }

        it "does not enqueue a pay in advance job" do
          expect { process_service.call }.not_to have_enqueued_job(Events::PayInAdvanceJob)
        end
      end

      context "when the contract is canceled" do
        let(:contract_status) { :canceled }

        it "does not enqueue a pay in advance job" do
          expect { process_service.call }.not_to have_enqueued_job(Events::PayInAdvanceJob)
        end
      end

      context "when the rate card bills in arrears" do
        let(:effective_date) { timestamp.to_date }
        let(:billing_timing) { :arrears }

        it "does not enqueue a pay in advance job" do
          expect { process_service.call }.not_to have_enqueued_job(Events::PayInAdvanceJob)
        end
      end
    end

    describe "#check_targeted_wallets", :premium do
      let(:charge) { create(:standard_charge, plan:, billable_metric:, organization:) }
      let(:accepts_target_wallet) { false }
      let(:event_properties) { {"target_wallet_code" => target_wallet_code} }
      let(:target_wallet_code) { "my_wallet" }

      before do
        organization.update!(premium_integrations: ["events_targeting_wallets"])
        charge.update!(accepts_target_wallet:)
      end

      context "when events_targeting_wallets feature is not enabled" do
        before do
          organization.update!(premium_integrations: [])
        end

        it "does not send error webhook" do
          expect { process_service.call }.not_to have_enqueued_job(SendWebhookJob)
        end
      end

      context "when target_wallet_code is not present in event properties" do
        let(:event_properties) { {} }

        it "does not send error webhook" do
          expect { process_service.call }.not_to have_enqueued_job(SendWebhookJob)
        end
      end

      context "when charge does not accept wallet target" do
        let(:accepts_target_wallet) { false }

        it "does not send error webhook" do
          expect { process_service.call }.not_to have_enqueued_job(SendWebhookJob)
        end
      end

      context "when charge accepts wallet target" do
        let(:accepts_target_wallet) { true }

        context "when wallet with target code exists" do
          before do
            create(:wallet, customer:, code: target_wallet_code)
          end

          it "does not send error webhook" do
            expect { process_service.call }.not_to have_enqueued_job(SendWebhookJob).with("event.error", anything, anything)
          end
        end

        context "when active wallet with target code does not exist" do
          let(:wallet) { create(:wallet, customer:, code: target_wallet_code, status: :terminated) }

          before { wallet }

          it "sends error webhook with target_wallet_code_not_found" do
            expect { process_service.call }.to have_enqueued_job(SendWebhookJob)
              .with("event.error", event, {error: {target_wallet_code: ["target_wallet_code_not_found"]}})
          end
        end
      end
    end
  end
end
