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

  describe "#call" do
    context "when relying on event codes" do
      it "returns the filtered charge_ids" do
        result = filter_service.call

        expect(result).to be_success
        expect(result.charges).to eq({})
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
          result = filter_service.call

          expect(result).to be_success
          expect(result.charges).to eq({charge.id => [nil]})
        end

        context "with multiple charges for the same billable_metric" do
          let(:charge_2) { create(:standard_charge, plan:, billable_metric:) }

          before { charge_2 }

          it "returns filtered charges" do
            result = filter_service.call

            expect(result).to be_success
            expect(result.charges).to eq({charge.id => [nil], charge_2.id => [nil]})
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
            result = filter_service.call

            expect(result).to be_success
            expect(result.charges).to eq({charge.id => [nil], charge_2.id => [nil]})
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
            result = filter_service.call

            expect(result).to be_success
            expect(result.charges).to match({charge.id => contain_exactly(charge_filter.id, charge_filter2.id, nil)})
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
          result = filter_service.call

          expect(result).to be_success
          expect(result.charges).to eq({recurring_charge.id => [charge_filter.id, nil]})
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
          result = filter_service.call

          expect(result).to be_success
          expect(result.charges).to eq({})
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
          result = filter_service.call

          expect(result).to be_success
          expect(result.charges).to eq({})
        end
      end
    end

    context "when relying on clickhouse enriched events", clickhouse: true do
      let(:organization) do
        create(:organization, clickhouse_events_store: true, pre_filter_events: true)
      end

      it "returns filtered charges" do
        result = filter_service.call

        expect(result).to be_success
        expect(result.charges).to eq({})
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
          result = filter_service.call

          expect(result).to be_success
          expect(result.charges).to eq({charge.id => [nil]})
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
            result = filter_service.call

            expect(result).to be_success
            expect(result.charges).to eq({charge.id => [nil], charge_2.id => [nil]})
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
            result = filter_service.call

            expect(result).to be_success
            expect(result.charges).to eq({charge.id => [nil], charge_2.id => [nil]})
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
            result = filter_service.call

            expect(result).to be_success
            expect(result.charges).to match({charge.id => contain_exactly(charge_filter.id)})
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
              result = filter_service.call

              expect(result).to be_success
              expect(result.charges).to match({charge.id => [nil]})
            end
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
          result = filter_service.call

          expect(result).to be_success
          expect(result.charges).to eq({recurring_charge.id => [charge_filter.id, nil]})
        end
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
          result = filter_service.call

          expect(result).to be_success
          expect(result.charges).to eq({})
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
          result = filter_service.call

          expect(result).to be_success
          expect(result.charges).to eq({})
        end
      end
    end
  end
end
