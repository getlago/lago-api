# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilterService do
  subject(:filter_result) { described_class.for_charges!(subscription:, boundaries:) }

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

    context "without billing segments when event pre-filtering is enabled" do
      subject(:filter_result) do
        described_class.for_billing_segments!(contract:, billing_segments: [])
      end

      let(:organization) { create(:organization, pre_filter_events: true) }

      it "succeeds with no filter targets" do
        result = filter_result

        expect(result).to be_success
        expect(result.filter_targets).to eq({})
      end
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

        context "when event pre-filtering is enabled" do
          let(:organization) { create(:organization, pre_filter_events: true) }

          it "matches the product filter using raw event properties" do
            result = filter_result

            expect(result).to be_success
            expect(result.filter_targets.transform_values(&:keys)).to eq({product.target_key => [product_filter.id]})
          end
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

    context "with a relation containing segments sharing a billable metric" do
      subject(:filter_result) do
        described_class.for_billing_segments!(contract:, billing_segments: contract.billing_segments)
      end

      before do
        billing_segment
        create(:billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate:,
          cycle_started_at: billing_segment.cycle_started_at + 1.month,
          started_at: billing_segment.started_at + 1.month, ended_at: billing_segment.ended_at + 1.month)
        create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us])
      end

      it "queries distinct metric codes and filter keys" do
        event_store = instance_double(Events::Stores::PostgresStore, distinct_codes_and_property_combinations: [])
        allow(Events::Stores::StoreFactory).to receive(:new_instance).and_return(event_store)

        filter_result

        expect(event_store).to have_received(:distinct_codes_and_property_combinations)
          .with(codes: [billable_metric.code], filter_keys: ["region"], with_last_seen_at: true)
      end
    end

    context "with recurring product usage" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }

      it "seeds the default bucket without events" do
        expect(filter_result.filter_targets).to eq({product.target_key => {nil => billing_segment.started_at}})
      end

      it "uses the combined period start for segments sharing a product" do
        later_segment = create(:billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate:,
          cycle_started_at: billing_segment.cycle_started_at + 1.month,
          started_at: billing_segment.started_at + 1.month, ended_at: billing_segment.ended_at + 1.month)

        result = described_class.for_billing_segments!(contract:, billing_segments: [later_segment, billing_segment])

        expect(result.filter_targets).to eq({product.target_key => {nil => billing_segment.started_at}})
      end

      context "with product filters" do
        let(:product_filter) { create(:product_filter, organization:, product:) }
        let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }

        before do
          create(:product_filter_value, organization:, product_filter:, billable_metric_filter:, value: "eu")
        end

        it "seeds current filters and the default bucket without events" do
          expect(filter_result.filter_targets).to eq({product.target_key => {
            product_filter.id => billing_segment.started_at,
            nil => billing_segment.started_at
          }})
        end

        context "with a backdated event ingested after the period start" do
          let(:ingested_at) { billing_segment.started_at + 2.days }

          before do
            create(:event, organization_id: organization.id, external_subscription_id: contract.external_id,
              code: billable_metric.code, properties: {"region" => "eu"},
              timestamp: billing_segment.started_at - 1.month, created_at: ingested_at)
          end

          it "updates the historical usage bucket with the ingestion timestamp" do
            expect(filter_result.filter_targets).to eq({product.target_key => {
              product_filter.id => ingested_at,
              nil => billing_segment.started_at
            }})
          end

          context "when timestamp aggregation is disabled" do
            subject(:filter_result) do
              described_class.for_billing_segments!(contract:, billing_segments: [billing_segment], with_last_seen_at: false)
            end

            it "retains the seeded timestamps" do
              expect(filter_result.filter_targets).to eq({product.target_key => {
                product_filter.id => billing_segment.started_at,
                nil => billing_segment.started_at
              }})
            end
          end
        end
      end

      it "separates period-only codes from recurring history and forwards timestamp options" do
        event_store = instance_double(Events::Stores::PostgresStore, distinct_codes_and_property_combinations: [])
        allow(Events::Stores::StoreFactory).to receive(:new_instance).and_return(event_store)

        described_class.for_billing_segments!(contract:, billing_segments: [billing_segment],
          codes: [billable_metric.code, "other_code"], with_last_seen_at: false)

        expect(event_store).to have_received(:distinct_codes_and_property_combinations)
          .with(codes: ["other_code"], filter_keys: [], with_last_seen_at: false)
        expect(event_store).to have_received(:distinct_codes_and_property_combinations)
          .with(codes: [billable_metric.code], filter_keys: [], include_all_history: true, with_last_seen_at: false)
      end

      it "does not seed recurring products excluded by explicit codes" do
        result = described_class.for_billing_segments!(contract:, billing_segments: [billing_segment], codes: ["unknown_code"])

        expect(result.filter_targets).to eq({})
      end

      it "ignores events after the segment end" do
        create(:event, organization_id: organization.id, external_subscription_id: contract.external_id,
          code: billable_metric.code, timestamp: billing_segment.ended_at + 1.day,
          created_at: billing_segment.ended_at + 2.days)

        expect(filter_result.filter_targets).to eq({product.target_key => {nil => billing_segment.started_at}})
      end
    end

    context "with non-recurring usage before the segment start" do
      before do
        create(:event, organization_id: organization.id, external_subscription_id: contract.external_id,
          code: billable_metric.code, timestamp: billing_segment.started_at - 1.day)
      end

      it "does not carry historical usage forward" do
        expect(filter_result.filter_targets).to eq({})
      end
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

          context "when event pre-filtering is enabled" do
            let(:organization) { create(:organization, pre_filter_events: true) }

            it "matches only the charge filter selected by raw event properties" do
              result = filter_result

              expect(result).to be_success
              expect(result.filter_targets.transform_values(&:keys)).to eq({charge.target_key => [charge_filter.id]})
            end
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
