# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilterService do
  subject(:filter_result) { described_class.for_charges!(subscription:, boundaries:) }

  shared_examples "recurring billable metric filtering" do
    let(:recurring_billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
    let(:recurring_charge) { create(:standard_charge, plan:, billable_metric: recurring_billable_metric) }

    let(:charge_filter) { create(:charge_filter, charge: recurring_charge) }
    let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric: recurring_billable_metric, key: "region", values: ["eu", "us"]) }

    let(:charge_filter_value) do
      create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
    end

    before do
      recurring_charge
      charge_filter_value
    end

    context "when it is the first billing period" do
      let(:started_at) { boundaries.charges_from_datetime }

      it "returns empty hash" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets.transform_values(&:keys)).to eq({})
      end
    end

    context "when previous fees exist" do
      let(:fee) { create(:charge_fee, subscription:, charge: recurring_charge, charge_filter:, units: 2.4) }

      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          invoice: fee.invoice,
          subscription:,
          organization:,
          charges_from_datetime: boundaries.charges_from_datetime - 1.month
        )
      end

      before { invoice_subscription }

      it "returns only charge/filter pairs from previous fees" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets.transform_values(&:keys)).to eq({recurring_charge.target_key => [charge_filter.id]})
      end

      it "seeds the carried-over usage with the period start" do
        result = filter_result

        expect(result.filter_targets[recurring_charge.target_key][charge_filter.id]).to eq(boundaries.charges_from_datetime)
      end
    end

    context "when no previous fees exist" do
      let(:invoice) { create(:invoice, organization:) }
      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          invoice:,
          subscription:,
          organization:,
          charges_from_datetime: boundaries.charges_from_datetime - 1.month
        )
      end

      before { invoice_subscription }

      it "returns empty hash" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets.transform_values(&:keys)).to eq({})
      end
    end

    context "when previous fees exist and have no units" do
      let(:invoice) { create(:invoice, organization:) }
      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          invoice:,
          subscription:,
          organization:,
          charges_from_datetime: boundaries.charges_from_datetime - 1.month
        )
      end

      let(:fee) { create(:charge_fee, subscription:, charge: recurring_charge, charge_filter:, units: 0, invoice:) }

      before { invoice_subscription }

      it "returns empty hash" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets.transform_values(&:keys)).to eq({})
      end
    end

    context "when subscription has previous_subscription_id" do
      let(:old_plan) { create(:plan, organization:) }
      let(:previous_subscription) do
        create(:subscription, :terminated, organization:, customer:, plan: old_plan, external_id: "sub_id", started_at: started_at - 1.month)
      end
      let(:subscription) do
        create(
          :subscription,
          organization:,
          customer:,
          plan:,
          started_at:,
          subscription_at: started_at,
          external_id: "sub_id",
          previous_subscription: previous_subscription
        )
      end

      context "when no filters on either side" do
        let(:charge_filter) { nil }
        let(:charge_filter_value) { nil }
        let(:recurring_charge) { create(:standard_charge, plan:, billable_metric: recurring_billable_metric) }
        let(:old_charge) { create(:standard_charge, plan: old_plan, billable_metric: recurring_billable_metric) }

        before do
          create(
            :charge_fee,
            subscription: previous_subscription,
            charge: old_charge,
            charge_filter_id: nil,
            created_at: started_at - 1.day,
            units: 2.4
          )
        end

        it "returns current charge with nil filter" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({recurring_charge.target_key => [nil]})
        end
      end

      context "when old has filters but current does not" do
        let(:charge_filter) { nil }
        let(:charge_filter_value) { nil }
        let(:recurring_charge) { create(:standard_charge, plan:, billable_metric: recurring_billable_metric) }
        let(:old_charge) { create(:standard_charge, plan: old_plan, billable_metric: recurring_billable_metric) }
        let(:old_filter) { create(:charge_filter, charge: old_charge) }

        before do
          create(
            :charge_fee,
            subscription: previous_subscription,
            charge: old_charge,
            charge_filter: old_filter,
            created_at: started_at - 1.day,
            units: 2.4
          )
        end

        it "returns current charge with nil filter" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({recurring_charge.target_key => [nil]})
        end
      end

      context "when old has filters with no units and current does not" do
        let(:charge_filter) { nil }
        let(:charge_filter_value) { nil }
        let(:recurring_charge) { create(:standard_charge, plan:, billable_metric: recurring_billable_metric) }
        let(:old_charge) { create(:standard_charge, plan: old_plan, billable_metric: recurring_billable_metric) }
        let(:old_filter) { create(:charge_filter, charge: old_charge) }

        before do
          create(
            :charge_fee,
            subscription: previous_subscription,
            charge: old_charge,
            charge_filter: old_filter,
            created_at: started_at - 1.day,
            units: 0
          )
        end

        it "returns empty hash" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({})
        end
      end

      context "when old has no filters but current has filters" do
        let(:old_charge) { create(:standard_charge, plan: old_plan, billable_metric: recurring_billable_metric) }

        before do
          create(
            :charge_fee,
            subscription: previous_subscription,
            charge: old_charge,
            charge_filter_id: nil,
            created_at: started_at - 1.day,
            units: 2.4
          )
        end

        it "returns all current filter IDs plus nil" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to match({recurring_charge.target_key => contain_exactly(charge_filter.id, nil)})
        end
      end

      context "when both have filters" do
        let(:old_charge) { create(:standard_charge, plan: old_plan, billable_metric: recurring_billable_metric) }
        let(:old_filter) { create(:charge_filter, charge: old_charge) }

        before do
          create(
            :charge_fee,
            subscription: previous_subscription,
            charge: old_charge,
            charge_filter: old_filter,
            created_at: started_at - 1.day,
            units: 2.4
          )
        end

        it "returns all current filter IDs plus nil" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to match({recurring_charge.target_key => contain_exactly(charge_filter.id, nil)})
        end
      end

      context "when traversing a chain of subscriptions" do
        let(:oldest_plan) { create(:plan, organization:) }
        let(:oldest_subscription) do
          create(:subscription, :terminated, organization:, customer:, plan: oldest_plan, external_id: "sub_id", started_at: started_at - 2.months)
        end
        let(:previous_subscription) do
          create(:subscription, :terminated, organization:, customer:, plan: old_plan, external_id: "sub_id", started_at: started_at - 1.month, previous_subscription: oldest_subscription)
        end
        let(:oldest_charge) { create(:standard_charge, plan: oldest_plan, billable_metric: recurring_billable_metric) }

        let(:fee) do
          create(
            :charge_fee,
            subscription: oldest_subscription,
            charge: oldest_charge,
            charge_filter_id: nil,
            created_at: started_at - 2.months + 1.day,
            units: 2.4
          )
        end

        before { fee }

        it "picks up fees from the entire chain" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to match({recurring_charge.target_key => contain_exactly(charge_filter.id, nil)})
        end

        context "when previous fees have no units" do
          let(:fee) do
            create(
              :charge_fee,
              subscription: oldest_subscription,
              charge: oldest_charge,
              charge_filter_id: nil,
              created_at: started_at - 2.months + 1.day,
              units: 0
            )
          end

          it "returns empty hash" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to eq({})
          end
        end
      end

      context "when no previous fees exist for recurring BMs" do
        it "returns empty hash" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({})
        end
      end

      context "when previous fees include both nil and non-nil charge_filter_id" do
        let(:old_charge) { create(:standard_charge, plan: old_plan, billable_metric: recurring_billable_metric) }
        let(:old_filter) { create(:charge_filter, charge: old_charge) }

        before do
          create(
            :charge_fee,
            subscription: previous_subscription,
            charge: old_charge,
            charge_filter: old_filter,
            created_at: started_at - 1.day,
            units: 2.4
          )
          create(
            :charge_fee,
            subscription: previous_subscription,
            charge: old_charge,
            charge_filter_id: nil,
            created_at: started_at - 1.day,
            units: 2.4
          )
        end

        it "returns all current filter IDs plus nil" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to match({recurring_charge.target_key => contain_exactly(charge_filter.id, nil)})
        end
      end
    end

    context "when previous fee has a discarded charge_filter" do
      let(:fee) { create(:charge_fee, subscription:, charge: recurring_charge, charge_filter:) }

      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          invoice: fee.invoice,
          subscription:,
          organization:,
          charges_from_datetime: boundaries.charges_from_datetime - 1.month
        )
      end

      before do
        invoice_subscription
        charge_filter.discard!
      end

      it "excludes the discarded filter from results" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets.transform_values(&:keys)).to eq({})
      end
    end
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:subscription) do
    create(
      :subscription,
      organization:,
      customer:,
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
  let(:charge_filter) { nil }
  let(:charge_filter_value) { nil }

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

  describe ".for_charges!" do
    it "runs through the class-level service entrypoint" do
      allow(described_class).to receive(:call!).and_call_original

      filter_result

      expect(described_class).to have_received(:call!)
        .with(resolver: an_instance_of(Events::BillingPeriodFilters::ChargesResolver))
    end
  end

  describe ".for_billing_segments!" do
    subject(:filter_result) do
      described_class.for_billing_segments!(contract:, billing_segments: [billing_segment])
    end

    let(:contract) { create(:contract, organization:, customer:, external_id: "contract_external_id") }
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
        cycle_started_at: boundaries.charges_from_datetime,
        started_at: boundaries.charges_from_datetime,
        ended_at: boundaries.charges_to_datetime
      )
    end

    it "runs through the class-level service entrypoint" do
      allow(described_class).to receive(:call!).and_call_original

      filter_result

      expect(described_class).to have_received(:call!)
        .with(resolver: an_instance_of(Events::BillingPeriodFilters::BillingSegmentsResolver))
    end

    context "with events matching billing segment products" do
      before do
        create(
          :event,
          organization_id: organization.id,
          external_subscription_id: contract.external_id,
          timestamp: billing_segment.started_at + 5.days,
          code: billable_metric.code,
          properties: {"region" => "eu"}
        )
      end

      context "without product filters" do
        it "returns the product default bucket" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({product.target_key => [nil]})
        end
      end

      context "with product filters" do
        let(:product_filter) { create(:product_filter, organization:, product:) }
        let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
        let(:product_filter_value) do
          create(:product_filter_value, organization:, product_filter:, billable_metric_filter:, value: "eu")
        end

        before { product_filter_value }

        it "returns the matching product filter keyed by product" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({product.target_key => [product_filter.id]})
        end

        it "returns the last seen timestamp for the product filter" do
          result = filter_result

          expect(result.filter_targets[product.target_key][product_filter.id]).to be_present
        end

        context "when the product filter selects the key only" do
          let(:product_filter_value) do
            create(:product_filter_value, organization:, product_filter:, billable_metric_filter:, value: nil)
          end

          it "matches any event carrying the key" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to eq({product.target_key => [product_filter.id]})
          end
        end
      end
    end

    it "queries raw event property combinations for billing segment products" do
      billable_metric_filter = create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us])
      product_filter = create(:product_filter, organization:, product:)
      create(:product_filter_value, organization:, product_filter:, billable_metric_filter:, value: "eu")
      event_store = instance_double(Events::Stores::PostgresStore, distinct_codes_and_property_combinations: [])
      allow(Events::Stores::StoreFactory).to receive(:new_instance).and_return(event_store)

      filter_result

      expect(event_store).to have_received(:distinct_codes_and_property_combinations)
        .with(codes: [billable_metric.code], filter_keys: ["region"], with_last_seen_at: true)
    end

    context "when codes restrict the lookup" do
      subject(:filter_result) do
        described_class.for_billing_segments!(contract:, billing_segments: [billing_segment], codes: ["unknown_code"])
      end

      before do
        create(
          :event,
          organization_id: organization.id,
          external_subscription_id: contract.external_id,
          timestamp: billing_segment.started_at + 5.days,
          code: billable_metric.code
        )
      end

      it "returns no billing segment target for other codes" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets).to eq({})
      end
    end
  end

  describe "#call" do
    context "when relying on event codes" do
      it "returns the filtered charge_ids" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets.transform_values(&:keys)).to eq({})
      end

      context "with events matching the boundaries" do
        before do
          create(
            :event,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            timestamp: boundaries.charges_from_datetime + 5.days,
            code: billable_metric.code,
            properties: {"region" => charge_filter_value&.values&.first}
          )

          create(
            :event,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            timestamp: boundaries.charges_from_datetime + 5.days,
            code: billable_metric.code,
            properties: {"region" => charge_filter_value&.values&.last}
          )
        end

        it "returns filtered charges" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [nil]})
        end

        it "returns the last seen timestamp per charge/filter" do
          result = filter_result

          expect(result.filter_targets[charge.target_key].keys).to eq([nil])
          expect(result.filter_targets[charge.target_key][nil]).to be_present
        end

        context "with multiple charges for the same billable_metric" do
          let(:charge_2) { create(:standard_charge, plan:, billable_metric:) }

          before { charge_2 }

          it "returns filtered charges" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [nil], charge_2.target_key => [nil]})
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
              code: billable_metric_2.code,
              properties: {"region" => charge_filter_value&.values&.first}
            )
          end

          it "returns charges and filters for all billable metrics with matching events" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [nil], charge_2.target_key => [nil]})
          end
        end

        context "with charge filters" do
          let(:charge_filter) { create(:charge_filter, charge:) }
          let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: ["eu", "us"]) }

          let(:charge_filter_value) do
            create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
          end

          let(:charge_filter2) { create(:charge_filter, charge:) }

          before { charge_filter2 }

          it "returns the filters that the events can match" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to match({charge.target_key => contain_exactly(charge_filter.id, charge_filter2.id)})
          end
        end

        context "when events only match a subset of the charge filters" do
          let(:charge_filter) { create(:charge_filter, charge:) }
          let(:billable_metric_filter) do
            create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us])
          end
          let(:charge_filter_value) do
            create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
          end

          let(:charge_filter_us) { create(:charge_filter, charge:) }
          let(:charge_filter_us_value) do
            create(:charge_filter_value, charge_filter: charge_filter_us, billable_metric_filter:, values: ["us"])
          end

          before { charge_filter_us_value }

          it "returns only the filters that received matching events" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [charge_filter.id]})
          end
        end

        context "when an event matches no charge filter" do
          let(:charge_filter) { create(:charge_filter, charge:) }
          let(:billable_metric_filter) do
            create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us])
          end
          let(:charge_filter_value) do
            create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
          end

          before do
            create(
              :event,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              timestamp: boundaries.charges_from_datetime + 6.days,
              code: billable_metric.code,
              properties: {"region" => "us"}
            )
          end

          it "returns the default filter for the unmatched usage" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to match({charge.target_key => contain_exactly(charge_filter.id, nil)})
          end
        end
      end

      context "with recurring billable metric" do
        let(:recurring_billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
        let(:recurring_charge) { create(:standard_charge, plan:, billable_metric: recurring_billable_metric) }

        let(:charge_filter) { create(:charge_filter, charge: recurring_charge) }
        let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric: recurring_billable_metric, key: "region", values: ["eu", "us"]) }

        let(:charge_filter_value) do
          create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
        end

        before do
          recurring_charge
          charge_filter_value
        end

        it "returns recurring charge_ids even without events" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({recurring_charge.target_key => [charge_filter.id, nil]})
        end

        it "seeds every recurring bucket with the period start when there are no events" do
          result = filter_result

          expect(result.filter_targets[recurring_charge.target_key][charge_filter.id]).to eq(boundaries.charges_from_datetime)
          expect(result.filter_targets[recurring_charge.target_key][nil]).to eq(boundaries.charges_from_datetime)
        end

        context "with events in the period" do
          before do
            create(
              :event,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              timestamp: boundaries.charges_from_datetime + 5.days,
              code: recurring_billable_metric.code,
              properties: {"region" => "eu"}
            )
          end

          it "refreshes the matching bucket's last_seen_at while leaving the unmatched bucket seeded" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets[recurring_charge.target_key].keys).to match_array([charge_filter.id, nil])
            expect(result.filter_targets[recurring_charge.target_key][charge_filter.id]).to be > boundaries.charges_from_datetime
            expect(result.filter_targets[recurring_charge.target_key][nil]).to eq(boundaries.charges_from_datetime)
          end
        end

        context "with a backdated event ingested for a prior period" do
          before do
            create(
              :event,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              timestamp: boundaries.charges_from_datetime - 10.days,
              code: recurring_billable_metric.code,
              properties: {"region" => "eu"}
            )
          end

          it "refreshes the matching bucket's last_seen_at from the backdated event's ingestion time" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets[recurring_charge.target_key].keys).to match_array([charge_filter.id, nil])
            # The event's business timestamp is out of the period, but it was ingested now, so
            # the recurring bucket must reflect it to invalidate the lazy usage cache.
            expect(result.filter_targets[recurring_charge.target_key][charge_filter.id]).to be > boundaries.charges_from_datetime
            expect(result.filter_targets[recurring_charge.target_key][nil]).to eq(boundaries.charges_from_datetime)
          end
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

        it "returns filtered charges" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({})
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

        it "returns filtered charges" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({})
        end
      end

      it "scopes the event store query to the plan billable metric codes" do
        event_store = instance_double(Events::Stores::PostgresStore, distinct_codes_and_property_combinations: [])
        allow(Events::Stores::StoreFactory).to receive(:new_instance).and_return(event_store)

        filter_result

        expect(event_store).to have_received(:distinct_codes_and_property_combinations)
          .with(codes: [billable_metric.code], filter_keys: [], with_last_seen_at: true)
      end
    end

    context "when relying on clickhouse enriched events", clickhouse: true do
      let(:organization) do
        create(:organization, clickhouse_events_store: true, pre_filter_events: true)
      end

      it "returns filtered charges" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets.transform_values(&:keys)).to eq({})
      end

      context "with events matching the boundaries" do
        let(:events) do
          Clickhouse::EventsEnrichedExpanded.create!(
            transaction_id: SecureRandom.uuid,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            subscription_id: subscription.id,
            plan_id: plan.id,
            code: billable_metric.code,
            aggregation_type: billable_metric.aggregation_type,
            charge_id: charge.id,
            charge_version: charge.updated_at,
            charge_filter_id: charge_filter&.id,
            charge_filter_version: charge_filter&.updated_at,
            timestamp: boundaries.charges_from_datetime + 5.days,
            properties: {"region" => charge_filter_value&.values&.first},
            value: "12",
            decimal_value: 12.0,
            precise_total_amount_cents: nil
          )

          Clickhouse::EventsEnrichedExpanded.create!(
            transaction_id: SecureRandom.uuid,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            subscription_id: subscription.id,
            plan_id: plan.id,
            code: billable_metric.code,
            aggregation_type: billable_metric.aggregation_type,
            charge_id: charge.id,
            charge_version: charge.updated_at,
            charge_filter_id: charge_filter&.id,
            charge_filter_version: charge_filter&.updated_at,
            timestamp: boundaries.charges_from_datetime + 5.days,
            properties: {"region" => charge_filter_value&.values&.last},
            value: "12",
            decimal_value: 12.0,
            precise_total_amount_cents: nil
          )
        end

        before { events }

        it "returns filtered charges" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [nil]})
        end

        context "with multiple charges for the same billable_metric" do
          let(:charge_2) { create(:standard_charge, plan:, billable_metric:) }

          let(:events) do
            Clickhouse::EventsEnrichedExpanded.create!(
              transaction_id: SecureRandom.uuid,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              subscription_id: subscription.id,
              plan_id: plan.id,
              code: billable_metric.code,
              aggregation_type: billable_metric.aggregation_type,
              charge_id: charge.id,
              charge_version: charge.updated_at,
              charge_filter_id: charge_filter&.id,
              charge_filter_version: charge_filter&.updated_at,
              timestamp: boundaries.charges_from_datetime + 5.days,
              properties: {"region" => charge_filter_value&.values&.first},
              value: "12",
              decimal_value: 12.0,
              precise_total_amount_cents: nil
            )

            Clickhouse::EventsEnrichedExpanded.create!(
              transaction_id: SecureRandom.uuid,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              subscription_id: subscription.id,
              plan_id: plan.id,
              code: billable_metric.code,
              aggregation_type: billable_metric.aggregation_type,
              charge_id: charge_2.id,
              charge_version: charge_2.updated_at,
              charge_filter_id: charge_filter&.id,
              charge_filter_version: charge_filter&.updated_at,
              timestamp: boundaries.charges_from_datetime + 5.days,
              properties: {"region" => charge_filter_value&.values&.last},
              value: "12",
              decimal_value: 12.0,
              precise_total_amount_cents: nil
            )
          end

          it "returns filtered charges" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [nil], charge_2.target_key => [nil]})
          end
        end

        context "with multiple billable metrics" do
          let(:billable_metric_2) { create(:billable_metric, organization:) }
          let(:charge_2) { create(:standard_charge, plan:, billable_metric: billable_metric_2) }

          before do
            charge_2

            Clickhouse::EventsEnrichedExpanded.create!(
              transaction_id: SecureRandom.uuid,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              subscription_id: subscription.id,
              plan_id: plan.id,
              code: billable_metric.code,
              aggregation_type: billable_metric.aggregation_type,
              charge_id: charge_2.id,
              charge_version: charge_2.updated_at,
              charge_filter_id: charge_filter&.id,
              charge_filter_version: charge_filter&.updated_at,
              timestamp: boundaries.charges_from_datetime + 5.days,
              properties: {"region" => charge_filter_value&.values&.last},
              value: "12",
              decimal_value: 12.0,
              precise_total_amount_cents: nil
            )
          end

          it "returns charges and filters for all billable metrics with matching events" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [nil], charge_2.target_key => [nil]})
          end
        end

        context "with charge filters" do
          let(:charge_filter) { create(:charge_filter, charge:) }
          let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: ["eu", "us"]) }

          let(:charge_filter_value) do
            create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
          end

          let(:charge_filter2) { create(:charge_filter, charge:) }

          before { charge_filter2 }

          it "returns charges and filters for all billable metrics with matching events" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to match({charge.target_key => contain_exactly(charge_filter.id)})
          end

          context "when events matches the default bucket" do
            let(:events) do
              Clickhouse::EventsEnrichedExpanded.create!(
                transaction_id: SecureRandom.uuid,
                organization_id: organization.id,
                external_subscription_id: subscription.external_id,
                subscription_id: subscription.id,
                plan_id: plan.id,
                code: billable_metric.code,
                aggregation_type: billable_metric.aggregation_type,
                charge_id: charge.id,
                charge_version: charge.updated_at,
                timestamp: boundaries.charges_from_datetime + 5.days,
                properties: {"region" => charge_filter_value&.values&.first},
                value: "12",
                decimal_value: 12.0,
                precise_total_amount_cents: nil
              )

              Clickhouse::EventsEnrichedExpanded.create!(
                transaction_id: SecureRandom.uuid,
                organization_id: organization.id,
                external_subscription_id: subscription.external_id,
                subscription_id: subscription.id,
                plan_id: plan.id,
                code: billable_metric.code,
                aggregation_type: billable_metric.aggregation_type,
                charge_id: charge.id,
                charge_version: charge.updated_at,
                timestamp: boundaries.charges_from_datetime + 5.days,
                properties: {"region" => charge_filter_value&.values&.last},
                value: "12",
                decimal_value: 12.0,
                precise_total_amount_cents: nil
              )
            end

            before { charge_filter }

            it "returns charges and filters for all billable metrics with matching events" do
              result = filter_result

              expect(result).to be_success
              expect(result.filter_targets.transform_values(&:keys)).to match({charge.target_key => [nil]})
            end
          end
        end
      end

      context "with recurring billable metric" do
        it_behaves_like "recurring billable metric filtering"
      end

      context "with unknown charges" do
        before do
          Clickhouse::EventsEnrichedExpanded.create!(
            transaction_id: SecureRandom.uuid,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            subscription_id: subscription.id,
            plan_id: plan.id,
            code: billable_metric.code,
            aggregation_type: billable_metric.aggregation_type,
            charge_id: SecureRandom.uuid,
            charge_version: boundaries.charges_from_datetime - 3.days,
            charge_filter_id: charge_filter&.id,
            charge_filter_version: charge_filter&.updated_at,
            timestamp: boundaries.charges_from_datetime + 5.days,
            properties: {"region" => charge_filter_value&.values&.last},
            value: "12",
            decimal_value: 12.0,
            precise_total_amount_cents: nil
          )
        end

        it "returns filtered charges" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({})
        end
      end

      context "with events that does not match the boundaries" do
        before do
          Clickhouse::EventsEnrichedExpanded.create!(
            transaction_id: SecureRandom.uuid,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            subscription_id: subscription.id,
            plan_id: plan.id,
            code: billable_metric.code,
            aggregation_type: billable_metric.aggregation_type,
            charge_id: charge.id,
            charge_version: charge.updated_at,
            timestamp: boundaries.charges_from_datetime - 5.days,
            properties: {"region" => charge_filter_value&.values&.first},
            value: "12",
            decimal_value: 12.0,
            precise_total_amount_cents: nil
          )
        end

        it "returns filtered charges" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({})
        end
      end
    end

    context "when relying on Postgres enriched events" do
      let(:organization) do
        create(:organization, pre_filter_events: true)
      end

      it "returns filtered charges" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets.transform_values(&:keys)).to eq({})
      end

      context "with events matching the boundaries" do
        let(:events) do
          [
            create(
              :event,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              code: billable_metric.code,
              timestamp: boundaries.charges_from_datetime + 5.days,
              properties: {"region" => charge_filter_value&.values&.first}
            ),
            create(
              :event,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              code: billable_metric.code,
              timestamp: boundaries.charges_from_datetime + 5.days,
              properties: {"region" => charge_filter_value&.values&.last}
            )
          ]
        end

        let(:enriched_events) do
          events.map do |event|
            create(
              :enriched_event,
              event:,
              subscription:,
              value: 12,
              decimal_value: 12.0,
              charge:,
              charge_filter_id: charge_filter&.id
            )
          end
        end

        before { enriched_events }

        it "returns filtered charges" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [nil]})
        end

        context "with multiple charges for the same billable_metric" do
          let(:charge_2) { create(:standard_charge, plan:, billable_metric:) }

          let(:enriched_events) do
            [
              create(
                :enriched_event,
                event: events.first,
                subscription:,
                value: 12,
                decimal_value: 12.0,
                charge:
              ),
              create(
                :enriched_event,
                event: events.last,
                subscription:,
                value: 12,
                decimal_value: 12.0,
                charge: charge_2
              )
            ]
          end

          it "returns filtered charges" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [nil], charge_2.target_key => [nil]})
          end
        end

        context "with multiple billable metrics" do
          let(:billable_metric_2) { create(:billable_metric, organization:) }
          let(:charge_2) { create(:standard_charge, plan:, billable_metric: billable_metric_2) }

          let(:events) do
            [
              create(
                :event,
                organization_id: organization.id,
                external_subscription_id: subscription.external_id,
                code: billable_metric.code,
                timestamp: boundaries.charges_from_datetime + 5.days,
                properties: {"region" => charge_filter_value&.values&.first}
              ),
              create(
                :event,
                organization_id: organization.id,
                external_subscription_id: subscription.external_id,
                code: billable_metric_2.code,
                timestamp: boundaries.charges_from_datetime + 5.days,
                properties: {"region" => charge_filter_value&.values&.last}
              )
            ]
          end

          let(:enriched_events) do
            [
              create(
                :enriched_event,
                event: events.first,
                subscription:,
                value: 12,
                decimal_value: 12.0,
                charge:
              ),
              create(
                :enriched_event,
                event: events.last,
                subscription:,
                value: 12,
                decimal_value: 12.0,
                charge: charge_2
              )
            ]
          end

          it "returns charges and filters for all billable metrics with matching events" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [nil], charge_2.target_key => [nil]})
          end
        end

        context "with charge filters" do
          let(:charge_filter) { create(:charge_filter, charge:) }
          let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: ["eu", "us"]) }

          let(:charge_filter_value) do
            create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
          end

          let(:charge_filter2) { create(:charge_filter, charge:) }

          before { charge_filter2 }

          it "returns charges and filters for all billable metrics with matching events" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to match({charge.target_key => contain_exactly(charge_filter.id)})
          end

          context "when events matches the default bucket" do
            let(:enriched_events) do
              [
                create(
                  :enriched_event,
                  event: events.first,
                  subscription:,
                  value: 12,
                  decimal_value: 12.0,
                  charge:
                ),
                create(
                  :enriched_event,
                  event: events.last,
                  subscription:,
                  value: 12,
                  decimal_value: 12.0,
                  charge:
                )
              ]
            end

            before { charge_filter }

            it "returns charges and filters for all billable metrics with matching events" do
              result = filter_result

              expect(result).to be_success
              expect(result.filter_targets.transform_values(&:keys)).to match({charge.target_key => [nil]})
            end
          end
        end
      end

      context "with recurring billable metric" do
        it_behaves_like "recurring billable metric filtering"

        context "with a backdated event ingested for a prior period" do
          let(:recurring_billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
          let(:recurring_charge) { create(:standard_charge, plan:, billable_metric: recurring_billable_metric) }

          let(:backdated_event) do
            create(
              :event,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              code: recurring_billable_metric.code,
              timestamp: boundaries.charges_from_datetime - 10.days
            )
          end

          let(:backdated_enriched_event) do
            create(
              :enriched_event,
              event: backdated_event,
              subscription:,
              value: 12,
              decimal_value: 12.0,
              charge: recurring_charge,
              charge_filter_id: nil
            )
          end

          before { backdated_enriched_event }

          it "includes the recurring charge with a last_seen_at from the backdated ingestion time" do
            result = filter_result

            expect(result).to be_success
            # The enriched event's business timestamp is out of the period, but it was ingested
            # now, so the recurring bucket must reflect it to invalidate the lazy usage cache.
            expect(result.filter_targets[recurring_charge.target_key][nil]).to be > boundaries.charges_from_datetime
          end
        end
      end

      context "with unknown charges" do
        let(:events) do
          [
            create(
              :event,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              code: billable_metric.code,
              timestamp: boundaries.charges_from_datetime + 5.days,
              properties: {"region" => charge_filter_value&.values&.first}
            )
          ]
        end

        let(:enriched_events) do
          events.map do |event|
            create(
              :enriched_event,
              event:,
              subscription:,
              value: 12,
              decimal_value: 12.0,
              charge: create(:standard_charge)
            )
          end
        end

        before do
          enriched_events
        end

        it "returns filtered charges" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({})
        end
      end

      context "with events that does not match the boundaries" do
        let(:events) do
          [
            create(
              :event,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              code: billable_metric.code,
              timestamp: boundaries.charges_from_datetime - 5.days,
              properties: {"region" => charge_filter_value&.values&.first}
            )
          ]
        end

        let(:enriched_events) do
          events.map do |event|
            create(
              :enriched_event,
              event:,
              subscription:,
              value: 12,
              decimal_value: 12.0,
              charge:
            )
          end
        end

        before { enriched_events }

        it "returns filtered charges" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({})
        end
      end

      context "with enriched events not matching the plan billable metric codes" do
        let(:events) do
          [
            create(
              :event,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              code: "unknown_code",
              timestamp: boundaries.charges_from_datetime + 5.days
            )
          ]
        end

        let(:enriched_events) do
          events.map do |event|
            create(
              :enriched_event,
              event:,
              subscription:,
              value: 12,
              decimal_value: 12.0,
              charge:
            )
          end
        end

        before { enriched_events }

        it "returns empty charges" do
          result = filter_result

          expect(result).to be_success
          expect(result.filter_targets.transform_values(&:keys)).to eq({})
        end
      end

      it "scopes the event store query to the plan billable metric codes" do
        event_store = instance_double(Events::Stores::PostgresStore, distinct_charges_and_filters: [])
        allow(Events::Stores::StoreFactory).to receive(:new_instance).and_return(event_store)

        filter_result

        expect(event_store).to have_received(:distinct_charges_and_filters)
          .with(codes: [billable_metric.code], with_last_seen_at: true)
      end
    end

    context "when last_seen_at is not requested" do
      subject(:filter_result) do
        described_class.for_charges!(subscription:, boundaries:, with_last_seen_at: false)
      end

      let(:default_result) { described_class.for_charges!(subscription:, boundaries:) }

      before do
        create(
          :event,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          timestamp: boundaries.charges_from_datetime + 5.days,
          code: billable_metric.code
        )
      end

      it "returns the same charges and filters as when it is requested" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets.transform_values(&:keys)).to eq(default_result.filter_targets.transform_values(&:keys))
      end

      it "returns no timestamp" do
        result = filter_result

        expect(result.filter_targets[charge.target_key]).to eq({nil => nil})
      end

      it "does not request the aggregate from the event store" do
        event_store = instance_double(Events::Stores::PostgresStore, distinct_codes_and_property_combinations: [])
        allow(Events::Stores::StoreFactory).to receive(:new_instance).and_return(event_store)

        filter_result

        expect(event_store).to have_received(:distinct_codes_and_property_combinations)
          .with(codes: [billable_metric.code], filter_keys: [], with_last_seen_at: false)
      end

      context "when the organization pre-filters events" do
        let(:organization) { create(:organization, pre_filter_events: true) }

        it "does not request the aggregate from the event store" do
          event_store = instance_double(Events::Stores::PostgresStore, distinct_charges_and_filters: [])
          allow(Events::Stores::StoreFactory).to receive(:new_instance).and_return(event_store)

          filter_result

          expect(event_store).to have_received(:distinct_charges_and_filters)
            .with(codes: [billable_metric.code], with_last_seen_at: false)
        end
      end
    end

    context "when codes restrict the lookup" do
      subject(:filter_result) do
        described_class.for_charges!(subscription:, boundaries:, codes: [billable_metric.code])
      end

      let(:billable_metric_2) { create(:billable_metric, organization:) }
      let(:charge_2) { create(:standard_charge, plan:, billable_metric: billable_metric_2) }

      before do
        charge_2

        [billable_metric, billable_metric_2].each do |metric|
          create(
            :event,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            timestamp: boundaries.charges_from_datetime + 5.days,
            code: metric.code
          )
        end
      end

      it "returns only the charges of the requested codes" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [nil]})
      end

      it "queries the event store for the requested codes only" do
        event_store = instance_double(Events::Stores::PostgresStore, distinct_codes_and_property_combinations: [])
        allow(Events::Stores::StoreFactory).to receive(:new_instance).and_return(event_store)

        filter_result

        expect(event_store).to have_received(:distinct_codes_and_property_combinations)
          .with(codes: [billable_metric.code], filter_keys: [], with_last_seen_at: true)
      end

      # A code outside of the plan matches no event of the subscription, so it is forwarded as is
      # rather than intersected away: dropping it would remove the charge from the result and bill
      # it as zero units instead of surfacing the unknown code.
      it "forwards a code that is not part of the plan" do
        event_store = instance_double(Events::Stores::PostgresStore, distinct_codes_and_property_combinations: [])
        allow(Events::Stores::StoreFactory).to receive(:new_instance).and_return(event_store)

        described_class.for_charges!(subscription:, boundaries:, codes: [billable_metric.code, "unknown_code"])

        expect(event_store).to have_received(:distinct_codes_and_property_combinations)
          .with(codes: [billable_metric.code, "unknown_code"], filter_keys: [], with_last_seen_at: true)
      end

      it "still seeds recurring charges left out of the codes" do
        recurring_metric = create(:sum_billable_metric, :recurring, organization:)
        recurring_charge = create(:standard_charge, plan:, billable_metric: recurring_metric)

        result = filter_result

        expect(result.filter_targets[recurring_charge.target_key]).to eq({nil => boundaries.charges_from_datetime})
      end
    end
  end
end
