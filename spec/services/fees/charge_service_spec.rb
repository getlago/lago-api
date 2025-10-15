# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ChargeService do
  subject(:charge_subscription_service) do
    described_class.new(invoice:, charge:, subscription:, boundaries:, context:, apply_taxes:)
  end

  around { |test| lago_premium!(&test) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:context) { :finalize }
  let(:apply_taxes) { false }

  let(:subscription) do
    create(
      :subscription,
      organization:,
      status: :active,
      started_at: Time.zone.parse("2022-03-15"),
      customer:
    )
  end

  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: subscription.started_at.to_date.beginning_of_day,
      to_datetime: subscription.started_at.end_of_month.end_of_day,
      charges_from_datetime: subscription.started_at.beginning_of_day,
      charges_to_datetime: subscription.started_at.end_of_month.end_of_day,
      timestamp: subscription.started_at.end_of_month.end_of_day + 1.second,
      charges_duration: (
        subscription.started_at.end_of_month.end_of_day - subscription.started_at.beginning_of_month
      ).fdiv(1.day).ceil
    )
  end

  let(:invoice) do
    create(:invoice, customer:, organization:)
  end

  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
  let(:charge) do
    create(
      :standard_charge,
      plan: subscription.plan,
      billable_metric:,
      properties: {
        amount: "20"
      }
    )
  end

  describe ".call" do
    context "without filters" do
      it "creates a fee" do
        result = charge_subscription_service.call
        expect(result).to be_success
        expect(result.fees.count).to be_zero
      end

      context "with an event" do
        let(:event) do
          create(
            :event,
            organization: subscription.organization,
            subscription:,
            code: billable_metric.code,
            timestamp: boundaries.charges_to_datetime - 2.days
          )
        end

        before { event }

        it "creates a fee" do
          result = charge_subscription_service.call
          expect(result).to be_success
          expect(result.fees.first).to have_attributes(
            id: String,
            organization_id: organization.id,
            billing_entity_id: invoice.customer.billing_entity_id,
            invoice_id: invoice.id,
            charge_id: charge.id,
            amount_cents: 2000,
            precise_amount_cents: 2000.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: 1,
            unit_amount_cents: 2000,
            precise_unit_amount: 20,
            events_count: 1,
            payment_status: "pending"
          )
        end

        it "persists fee" do
          expect { charge_subscription_service.call }.to change(Fee, :count)
        end

        context "with preview context" do
          let(:context) { :invoice_preview }

          it "does not persist fee" do
            expect { charge_subscription_service.call }.not_to change(Fee, :count)
          end
        end
      end

      # TODO(pricing_group_keys): remove after deprecation of grouped_by
      context "with grouped standard charge" do
        let(:charge) do
          create(
            :standard_charge,
            plan: subscription.plan,
            billable_metric:,
            properties: {
              amount: "20",
              grouped_by: ["cloud"]
            }
          )
        end

        let(:billable_metric) do
          create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "value")
        end

        context "without events" do
          it "does not create a fee" do
            result = charge_subscription_service.call
            expect(result).to be_success
            expect(result.fees.count).to eq(0)
          end

          context "when organization as zero_amount_fees premium integration" do
            before do
              organization.update!(premium_integrations: ["zero_amount_fees"])
            end

            it "creates a fee" do
              result = charge_subscription_service.call
              expect(result).to be_success
              expect(result.fees.count).to eq(1)
            end
          end
        end

        context "with events" do
          before do
            create(
              :event,
              organization: subscription.organization,
              subscription:,
              code: charge.billable_metric.code,
              timestamp: Time.zone.parse("2022-03-16"),
              properties: {cloud: "aws", value: 10}
            )

            create(
              :event,
              organization: subscription.organization,
              subscription:,
              code: charge.billable_metric.code,
              timestamp: Time.zone.parse("2022-03-16"),
              properties: {cloud: "aws", value: 5}
            )

            create(
              :event,
              organization: subscription.organization,
              subscription:,
              code: charge.billable_metric.code,
              timestamp: Time.zone.parse("2022-03-16"),
              properties: {cloud: "gcp", value: 10}
            )
          end

          it "creates a fee for each group" do
            result = charge_subscription_service.call
            expect(result).to be_success
            expect(result.fees.count).to eq(2)

            fee1 = result.fees.find { |f| f.grouped_by["cloud"] == "aws" }
            expect(fee1).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 30_000,
              precise_amount_cents: 30_000.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 15,
              unit_amount_cents: 2000,
              precise_unit_amount: 20,
              grouped_by: {"cloud" => "aws"}
            )

            fee2 = result.fees.find { |f| f.grouped_by["cloud"] == "gcp" }
            expect(fee2).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 20_000,
              precise_amount_cents: 20_000.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 10,
              unit_amount_cents: 2000,
              precise_unit_amount: 20,
              grouped_by: {"cloud" => "gcp"}
            )
          end

          context "with adjusted fee" do
            let(:adjusted_fee) do
              create(
                :adjusted_fee,
                invoice:,
                subscription:,
                charge:,
                properties:,
                fee_type: :charge,
                adjusted_units: true,
                adjusted_amount: false,
                units: 3,
                grouped_by: {"cloud" => "aws"}
              )
            end

            let(:properties) do
              {
                charges_from_datetime: boundaries.charges_from_datetime,
                charges_to_datetime: boundaries.charges_to_datetime
              }
            end

            before do
              adjusted_fee
              invoice.draft!
            end

            it "creates a fee for each group" do
              result = charge_subscription_service.call
              expect(result).to be_success
              expect(result.fees.count).to eq(2)

              fee1 = result.fees.find { |f| f.grouped_by["cloud"] == "aws" }
              expect(fee1).to have_attributes(
                id: String,
                invoice_id: invoice.id,
                charge_id: charge.id,
                amount_cents: 6_000,
                precise_amount_cents: 6_000.0,
                taxes_precise_amount_cents: 0.0,
                amount_currency: "EUR",
                units: 3,
                unit_amount_cents: 2000,
                precise_unit_amount: 20,
                grouped_by: {"cloud" => "aws"}
              )

              fee2 = result.fees.find { |f| f.grouped_by["cloud"] == "gcp" }
              expect(fee2).to have_attributes(
                id: String,
                invoice_id: invoice.id,
                charge_id: charge.id,
                amount_cents: 20_000,
                precise_amount_cents: 20_000.0,
                taxes_precise_amount_cents: 0.0,
                amount_currency: "EUR",
                units: 10,
                unit_amount_cents: 2000,
                precise_unit_amount: 20,
                grouped_by: {"cloud" => "gcp"}
              )
            end
          end

          context "with recurring weighted sum aggregation" do
            let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }

            it "creates a fee and a cached aggregation per group" do
              result = charge_subscription_service.call
              expect(result).to be_success

              expect(result.fees.count).to eq(2)
              expect(result.cached_aggregations.count).to eq(2)
            end
          end

          context "with custom aggregation" do
            let(:billable_metric) do
              create(:custom_aggregation_billable_metric, organization:)

              it "creates a fee and a cached aggregation" do
                result = charge_subscription_service.call
                expect(result).to be_success

                expect(result.fees.count).to eq(2)
                expect(result.cached_aggregation.count).to eq(2)
              end
            end
          end
        end
      end

      context "with pricing_group_keys and standard charge" do
        let(:charge) do
          create(
            :standard_charge,
            plan: subscription.plan,
            billable_metric:,
            properties: {
              amount: "20",
              pricing_group_keys: ["cloud"]
            }
          )
        end

        let(:billable_metric) do
          create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "value")
        end

        context "with filters" do
          let(:charge) do
            create(
              :standard_charge,
              plan: subscription.plan,
              billable_metric:,
              properties: {
                amount: "20",
                pricing_group_keys: ["region", "country"]
              }
            )
          end
          let(:region) do
            create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu na])
          end
          let(:country) do
            create(:billable_metric_filter, billable_metric:, key: "country", values: %w[us ca fr de])
          end

          let(:eu_filter) do
            create(:charge_filter, charge:, properties: {amount: "30", pricing_group_keys: ["region", "country"]})
          end
          let(:eu_country_filter_value) { create(:charge_filter_value, charge_filter: eu_filter, billable_metric_filter: country, values: ["fr", "de"]) }
          let(:eu_region_filter_value) { create(:charge_filter_value, charge_filter: eu_filter, billable_metric_filter: region, values: ["eu"]) }

          let(:na_filter) do
            create(:charge_filter, charge:, properties: {amount: "40", pricing_group_keys: ["region", "country"]})
          end
          let(:na_country_filter_value) { create(:charge_filter_value, charge_filter: na_filter, billable_metric_filter: country, values: ["us", "ca"]) }
          let(:na_region_filter_value) { create(:charge_filter_value, charge_filter: na_filter, billable_metric_filter: region, values: ["na"]) }

          before do
            na_country_filter_value
            na_region_filter_value
            eu_country_filter_value
            eu_region_filter_value
            create_event("eu", "fr")
            create_event("eu", "de")
            create_event("na", "us")
            create_event("na", "ca")
            create_event("af", "ma")
            create_event("af", "ma")
            create_event("af", "dz")
          end

          def create_event(region, country)
            create(
              :event,
              organization: subscription.organization,
              subscription:,
              code: charge.billable_metric.code,
              timestamp: Time.zone.parse("2022-03-16"),
              properties: {region:, country:, value: 1}
            )
          end

          it "creates a fee for each group" do
            result = charge_subscription_service.call
            expect(result).to be_success
            expect(result.fees.count).to eq(6)

            sorted_fees = result.fees.sort_by { [it.grouped_by["region"], it.grouped_by["country"]] }

            af_dz_fee = sorted_fees[0]
            expect(af_dz_fee).to have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 2000,
              precise_amount_cents: 2000.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 1,
              unit_amount_cents: 2000,
              precise_unit_amount: 20,
              grouped_by: {"country" => "dz", "region" => "af"}
            )

            af_ma_fee = sorted_fees[1]
            expect(af_ma_fee).to have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 4000,
              precise_amount_cents: 4000.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 2,
              unit_amount_cents: 2000,
              precise_unit_amount: 20,
              grouped_by: {"country" => "ma", "region" => "af"}
            )

            eu_de = sorted_fees[2]
            expect(eu_de).to have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 3000,
              precise_amount_cents: 3000.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 1,
              unit_amount_cents: 3000,
              precise_unit_amount: 30,
              grouped_by: {"country" => "de", "region" => "eu"}
            )

            eu_fr = sorted_fees[3]
            expect(eu_fr).to have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 3000,
              precise_amount_cents: 3000.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 1,
              unit_amount_cents: 3000,
              precise_unit_amount: 30,
              grouped_by: {"country" => "fr", "region" => "eu"}
            )

            na_ca_fee = sorted_fees[4]
            expect(na_ca_fee).to have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 4000,
              precise_amount_cents: 4000.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 1,
              unit_amount_cents: 4000,
              precise_unit_amount: 40,
              grouped_by: {"country" => "ca", "region" => "na"}
            )

            na_us_fee = sorted_fees[5]
            expect(na_us_fee).to have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 4000,
              precise_amount_cents: 4000.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 1,
              unit_amount_cents: 4000,
              precise_unit_amount: 40,
              grouped_by: {"country" => "us", "region" => "na"}
            )
          end
        end

        context "without events" do
          it "does not create a fee" do
            result = charge_subscription_service.call
            expect(result).to be_success
            expect(result.fees.count).to eq(0)
          end

          context "when organization as zero_amount_fees premium integration" do
            before do
              organization.update!(premium_integrations: ["zero_amount_fees"])
            end

            it "creates a fee" do
              result = charge_subscription_service.call
              expect(result).to be_success
              expect(result.fees.count).to eq(1)
            end
          end
        end

        context "with events" do
          before do
            create(
              :event,
              organization: subscription.organization,
              subscription:,
              code: charge.billable_metric.code,
              timestamp: Time.zone.parse("2022-03-16"),
              properties: {cloud: "aws", value: 10}
            )

            create(
              :event,
              organization: subscription.organization,
              subscription:,
              code: charge.billable_metric.code,
              timestamp: Time.zone.parse("2022-03-16"),
              properties: {cloud: "aws", value: 5}
            )

            create(
              :event,
              organization: subscription.organization,
              subscription:,
              code: charge.billable_metric.code,
              timestamp: Time.zone.parse("2022-03-16"),
              properties: {cloud: "gcp", value: 10}
            )
          end

          it "creates a fee for each group" do
            result = charge_subscription_service.call
            expect(result).to be_success
            expect(result.fees.count).to eq(2)

            fee1 = result.fees.find { |f| f.grouped_by["cloud"] == "aws" }
            expect(fee1).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 30_000,
              precise_amount_cents: 30_000.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 15,
              unit_amount_cents: 2000,
              precise_unit_amount: 20,
              grouped_by: {"cloud" => "aws"}
            )

            fee2 = result.fees.find { |f| f.grouped_by["cloud"] == "gcp" }
            expect(fee2).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 20_000,
              precise_amount_cents: 20_000.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 10,
              unit_amount_cents: 2000,
              precise_unit_amount: 20,
              grouped_by: {"cloud" => "gcp"}
            )
          end

          context "with adjusted fee" do
            let(:adjusted_fee) do
              create(
                :adjusted_fee,
                invoice:,
                subscription:,
                charge:,
                properties:,
                fee_type: :charge,
                adjusted_units: true,
                adjusted_amount: false,
                units: 3,
                grouped_by: {"cloud" => "aws"}
              )
            end

            let(:properties) do
              {
                charges_from_datetime: boundaries.charges_from_datetime,
                charges_to_datetime: boundaries.charges_to_datetime
              }
            end

            before do
              adjusted_fee
              invoice.draft!
            end

            it "creates a fee for each group" do
              result = charge_subscription_service.call
              expect(result).to be_success
              expect(result.fees.count).to eq(2)

              fee1 = result.fees.find { |f| f.grouped_by["cloud"] == "aws" }
              expect(fee1).to have_attributes(
                id: String,
                invoice_id: invoice.id,
                charge_id: charge.id,
                amount_cents: 6_000,
                precise_amount_cents: 6_000.0,
                taxes_precise_amount_cents: 0.0,
                amount_currency: "EUR",
                units: 3,
                unit_amount_cents: 2000,
                precise_unit_amount: 20,
                grouped_by: {"cloud" => "aws"}
              )

              fee2 = result.fees.find { |f| f.grouped_by["cloud"] == "gcp" }
              expect(fee2).to have_attributes(
                id: String,
                invoice_id: invoice.id,
                charge_id: charge.id,
                amount_cents: 20_000,
                precise_amount_cents: 20_000.0,
                taxes_precise_amount_cents: 0.0,
                amount_currency: "EUR",
                units: 10,
                unit_amount_cents: 2000,
                precise_unit_amount: 20,
                grouped_by: {"cloud" => "gcp"}
              )
            end
          end

          context "with recurring weighted sum aggregation" do
            let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }

            it "creates a fee and a cached aggregation per group" do
              result = charge_subscription_service.call
              expect(result).to be_success

              expect(result.fees.count).to eq(2)
              expect(result.cached_aggregations.count).to eq(2)
            end
          end

          context "with custom aggregation" do
            let(:billable_metric) do
              create(:custom_aggregation_billable_metric, organization:)

              it "creates a fee and a cached aggregation" do
                result = charge_subscription_service.call
                expect(result).to be_success

                expect(result.fees.count).to eq(2)
                expect(result.cached_aggregation.count).to eq(2)
              end
            end
          end
        end
      end

      context "with graduated charge model" do
        let(:charge) do
          create(
            :graduated_charge,
            plan: subscription.plan,
            charge_model: "graduated",
            billable_metric:,
            properties: {
              graduated_ranges: [
                {
                  from_value: 0,
                  to_value: nil,
                  per_unit_amount: "0.01",
                  flat_amount: "0.01"
                }
              ]
            }
          )
        end

        before do
          create_list(
            :event,
            4,
            organization: subscription.organization,
            subscription:,
            code: charge.billable_metric.code,
            timestamp: Time.zone.parse("2022-03-16")
          )
        end

        it "creates a fee" do
          result = charge_subscription_service.call
          expect(result).to be_success
          expect(result.fees.first).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            charge_id: charge.id,
            amount_cents: 5,
            precise_amount_cents: 5.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: 4.0,
            unit_amount_cents: 1,
            precise_unit_amount: 0.0125,
            events_count: 4
          )
        end
      end

      context "when fee already exists on the period" do
        before do
          create(:fee, charge:, subscription:, invoice:)
        end

        it "does not create a new fee" do
          expect { charge_subscription_service.call }.not_to change(Fee, :count)
        end
      end

      context "when billing an new upgraded subscription" do
        let(:previous_plan) { create(:plan, amount_cents: subscription.plan.amount_cents - 20) }
        let(:previous_subscription) do
          create(:subscription, plan: previous_plan, status: :terminated)
        end

        let(:event) do
          create(
            :event,
            organization: invoice.organization,
            subscription:,
            code: billable_metric.code,
            timestamp: Time.zone.parse("10 Apr 2022 00:01:00")
          )
        end

        let(:boundaries) do
          BillingPeriodBoundaries.new(
            from_datetime: Time.zone.parse("15 Apr 2022 00:01:00"),
            to_datetime: Time.zone.parse("30 Apr 2022 00:01:00"),
            charges_from_datetime: subscription.started_at,
            charges_to_datetime: Time.zone.parse("30 Apr 2022 00:01:00"),
            charges_duration: 30,
            timestamp: Time.zone.parse("2022-05-01T00:01:00")
          )
        end

        before do
          subscription.update!(previous_subscription:)
          event
        end

        it "creates a new fee for the complete period" do
          result = charge_subscription_service.call
          expect(result).to be_success
          expect(result.fees.first).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            charge_id: charge.id,
            amount_cents: 2000,
            precise_amount_cents: 2_000.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: 1
          )
        end
      end

      context "with all types of aggregation" do
        let(:event) do
          create(
            :event,
            code: billable_metric.code,
            organization: organization,
            external_subscription_id: subscription.external_id,
            timestamp: boundaries.charges_to_datetime - 2.days,
            properties: {"foo_bar" => 1}
          )
        end

        BillableMetric::AGGREGATION_TYPES.keys.each do |aggregation_type|
          before do
            billable_metric.update!(
              aggregation_type:,
              field_name: event.properties.keys.first,
              weighted_interval: "seconds",
              custom_aggregator: "def aggregate(event, agg, aggregation_properties); { total_units: 1, amount: 1 }; end"
            )
          end

          context "without pricing unit on the charge" do
            it "creates fees" do
              result = charge_subscription_service.call
              expect(result).to be_success
              expect(result.fees.first).to have_attributes(
                id: String,
                invoice_id: invoice.id,
                charge_id: charge.id,
                amount_cents: 2000,
                precise_amount_cents: 2000.0,
                taxes_precise_amount_cents: 0.0,
                amount_currency: "EUR",
                units: 1,
                unit_amount_cents: 2000,
                precise_unit_amount: 20
              )
            end

            it "does not create pricing unit usage" do
              expect { charge_subscription_service.call }.not_to change(PricingUnitUsage, :count)
            end
          end

          context "with pricing unit on the charge" do
            before do
              create(
                :applied_pricing_unit,
                organization: subscription.organization,
                conversion_rate: 0.25,
                pricing_unitable: charge
              )
            end

            it "creates fees" do
              result = charge_subscription_service.call
              expect(result).to be_success
              expect(result.fees.first).to have_attributes(
                id: String,
                invoice_id: invoice.id,
                charge_id: charge.id,
                amount_cents: 500,
                precise_amount_cents: 500.0,
                taxes_precise_amount_cents: 0.0,
                amount_currency: "EUR",
                units: 1,
                unit_amount_cents: 500,
                precise_unit_amount: 5
              )
            end

            it "creates pricing unit usage" do
              result = charge_subscription_service.call
              expect(result).to be_success
              expect(result.fees.first.pricing_unit_usage)
                .to be_persisted
                .and have_attributes(
                  amount_cents: 2000,
                  precise_amount_cents: 2000.0,
                  unit_amount_cents: 2000
                )
            end
          end
        end
      end

      context "when there is adjusted fee" do
        let(:adjusted_fee) do
          create(
            :adjusted_fee,
            invoice:,
            subscription:,
            charge:,
            properties:,
            fee_type: :charge,
            adjusted_units: true,
            adjusted_amount: false,
            units: 3
          )
        end
        let(:properties) do
          {
            charges_from_datetime: boundaries.charges_from_datetime,
            charges_to_datetime: boundaries.charges_to_datetime
          }
        end

        before do
          adjusted_fee
          invoice.draft!
        end

        context "with adjusted units" do
          it "creates a fee" do
            result = charge_subscription_service.call

            expect(result).to be_success
            expect(result.fees.first).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 6_000,
              precise_amount_cents: 6_000.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 3,
              unit_amount_cents: 2_000,
              precise_unit_amount: 20,
              events_count: 0,
              payment_status: "pending"
            )
          end

          context "when there is true-up fee" do
            before { charge.update!(min_amount_cents: 20_000) }

            it "creates two fees" do
              result = charge_subscription_service.call

              aggregate_failures do
                expect(result).to be_success
                expect(result.fees.count).to eq(2)
                expect(result.fees.pluck(:amount_cents)).to contain_exactly(6_000, 4_968)
                expect(result.fees.pluck(:precise_amount_cents)).to contain_exactly(6_000.0, 4_967.74193548387)
                expect(result.fees.pluck(:taxes_precise_amount_cents)).to contain_exactly(0.0, 0.0)
                expect(result.fees.pluck(:unit_amount_cents)).to contain_exactly(2_000, 4_968)
                expect(result.fees.pluck(:precise_unit_amount)).to contain_exactly(20, 49.6774193548387)
              end
            end
          end

          context "with standard charge, all types of aggregation and presence of filters" do
            let(:region) do
              create(:billable_metric_filter, billable_metric:, key: "region", values: %w[europe usa])
            end

            let(:country) do
              create(:billable_metric_filter, billable_metric:, key: "country", values: ["france", "germany", "united kingdom"])
            end

            let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:, properties: {amount: "10"}) }

            let(:europe_filter) { create_filter(amount: "20", values: {region => ["europe"]}) }
            let(:usa_filter) { create_filter(amount: "30", values: {region => ["usa"]}) }
            let(:france_filter) { create_filter(amount: "40.12345", values: {region => ["europe"], country => ["france"]}) }
            let(:all_values_filter) do
              all_values = [ChargeFilterValue::ALL_FILTER_VALUES]
              create_filter(amount: "50", values: {region => all_values, country => all_values})
            end

            let(:adjusted_fee) do
              create(
                :adjusted_fee,
                invoice:,
                subscription:,
                charge:,
                charge_filter: usa_filter,
                properties:,
                fee_type: :charge,
                adjusted_units: true,
                adjusted_amount: false,
                units: 3
              )
            end

            before do
              region
              country

              europe_filter
              usa_filter
              france_filter
              all_values_filter

              # usa filter events
              create_event(properties: {region: "usa", foo_bar: 12})

              # europe filter events
              create_event(properties: {region: "europe", foo_bar: 10})
              create_event(properties: {region: "europe", foo_bar: 2})
              create_event(properties: {region: "europe", country: "italy", foo_bar: 3})

              # france filter events
              create_event(properties: {region: "europe", country: "france", foo_bar: 5})

              # All values filter events
              create_event(properties: {region: "europe", country: "united kingdom", foo_bar: 5})
              create_event(properties: {region: "europe", country: "germany", foo_bar: 5})

              # No filter events
              create_event(properties: {region: "asia", country: "japan", foo_bar: 3})
              create_event(properties: {foo_bar: 2})
            end

            def create_event(properties:)
              organization = subscription.organization
              code = charge.billable_metric.code
              create(:event, organization:, subscription:, code:, timestamp: Time.zone.parse("2022-03-16"), properties:)
            end

            def create_filter(amount:, values:)
              filter = create(:charge_filter, charge:, properties: {amount:})
              values.each do |billable_metric_filter, values|
                create(:charge_filter_value, charge_filter: filter, billable_metric_filter:, values:)
              end
              filter
            end

            it "creates expected fees for sum_agg aggregation type" do
              billable_metric.update!(aggregation_type: :sum_agg, field_name: "foo_bar")
              result = charge_subscription_service.call
              expect(result).to be_success
              created_fees = result.fees

              aggregate_failures do
                expect(created_fees.count).to eq(5)
                expect(created_fees).to all(
                  have_attributes(
                    invoice_id: invoice.id,
                    charge_id: charge.id,
                    amount_currency: "EUR"
                  )
                )

                usa_fee = created_fees.find { |f| f.charge_filter == usa_filter }
                expect(usa_fee).to have_attributes(
                  charge_filter: usa_filter,
                  amount_cents: 9_000,
                  precise_amount_cents: 9_000.0,
                  taxes_precise_amount_cents: 0.0,
                  units: 3,
                  unit_amount_cents: 3000,
                  precise_unit_amount: 30
                )

                europe_fee = created_fees.find { |f| f.charge_filter == europe_filter }
                expect(europe_fee).to have_attributes(
                  charge_filter: europe_filter,
                  amount_cents: 30_000,
                  precise_amount_cents: 30_000.0,
                  taxes_precise_amount_cents: 0.0,
                  units: 15,
                  unit_amount_cents: 2000,
                  precise_unit_amount: 20
                )

                france_fee = created_fees.find { |f| f.charge_filter == france_filter }
                expect(france_fee).to have_attributes(
                  charge_filter: france_filter,
                  amount_cents: 20062,
                  precise_amount_cents: 20061.725,
                  taxes_precise_amount_cents: 0.0,
                  units: 5,
                  unit_amount_cents: 4012,
                  precise_unit_amount: 40.12345
                )

                all_filter_fee = created_fees.find { |f| f.charge_filter == all_values_filter }
                expect(all_filter_fee).to have_attributes(
                  charge_filter: all_values_filter,
                  amount_cents: 50000,
                  precise_amount_cents: 50000.0,
                  taxes_precise_amount_cents: 0.0,
                  units: 10,
                  unit_amount_cents: 5000,
                  precise_unit_amount: 50.0
                )

                no_filter_fee = created_fees.find { |f| f.charge_filter.blank? }
                expect(no_filter_fee).to have_attributes(
                  charge_filter: nil,
                  amount_cents: 5000,
                  precise_amount_cents: 5000.0,
                  taxes_precise_amount_cents: 0.0,
                  units: 5,
                  unit_amount_cents: 1000,
                  precise_unit_amount: 10.0
                )
              end
            end
          end
        end

        context "with adjusted amount" do
          let(:adjusted_fee) do
            create(
              :adjusted_fee,
              invoice:,
              subscription:,
              charge:,
              properties:,
              fee_type: :charge,
              adjusted_units: false,
              adjusted_amount: true,
              units: 1000,
              unit_amount_cents: 0,
              unit_precise_amount_cents: 0.1
            )
          end

          it "creates a fee" do
            result = charge_subscription_service.call

            expect(result).to be_success
            expect(result.fees.first).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 100,
              precise_amount_cents: 100.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 1000,
              unit_amount_cents: 0,
              precise_unit_amount: 0.001,
              events_count: 0,
              payment_status: "pending"
            )
          end
        end

        context "with adjusted display name" do
          let(:adjusted_fee) do
            create(
              :adjusted_fee,
              invoice:,
              subscription:,
              charge:,
              properties:,
              fee_type: :charge,
              adjusted_units: false,
              adjusted_amount: false,
              invoice_display_name: "test123",
              units: 3
            )
          end

          it "creates a fee" do
            result = charge_subscription_service.call

            expect(result).to be_success
            expect(result.fees.first).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 0,
              precise_amount_cents: 0.0,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: 0,
              unit_amount_cents: 0,
              precise_unit_amount: 0,
              events_count: 0,
              payment_status: "pending",
              invoice_display_name: "test123"
            )
          end
        end

        context "with invoice NOT in draft status" do
          before { invoice.finalized! }

          it "creates a fee without using adjusted fee attributes" do
            result = charge_subscription_service.call

            expect(result).to be_success
            expect(result.fees.first).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 0,
              amount_currency: "EUR",
              units: 0,
              unit_amount_cents: 0,
              precise_unit_amount: 0,
              events_count: 0,
              payment_status: "pending"
            )
          end
        end
      end

      context "with true-up fee" do
        it "creates two fees" do
          travel_to(Time.zone.parse("2023-04-01")) do
            charge.update!(min_amount_cents: 1000)
            result = charge_subscription_service.call

            expect(result).to be_success
            expect(result.fees.count).to eq(2)
            expect(result.fees.pluck(:amount_cents)).to contain_exactly(0, 548) # 548 is 1000 prorated for 17 days.
            expect(result.fees.pluck(:precise_amount_cents)).to contain_exactly(0.0, 548.3870967741935) # 548 is 1000 prorated for 17 days.
            expect(result.fees.pluck(:taxes_precise_amount_cents)).to contain_exactly(0.0, 0.0) # 548 is 1000 prorated for 17 days.
            expect(result.fees.pluck(:unit_amount_cents)).to contain_exactly(0, 548)
            expect(result.fees.pluck(:precise_unit_amount)).to contain_exactly(0, 5.483870967741935)
          end
        end

        context "with charge using pricing units" do
          before do
            create(
              :applied_pricing_unit,
              organization: charge.organization,
              conversion_rate: 1,
              pricing_unitable: charge
            )
          end

          it "persists pricing unit usages" do
            travel_to(Time.zone.parse("2023-04-01")) do
              charge.update!(min_amount_cents: 1000)
              result = charge_subscription_service.call

              expect(result).to be_success
              expect(result.fees.map(&:pricing_unit_usage)).to all be_persisted
            end
          end
        end
      end

      context "with negative units" do
        let(:charge) do
          create(
            :graduated_charge,
            plan: subscription.plan,
            charge_model: "graduated",
            billable_metric:,
            properties: {
              graduated_ranges: [
                {
                  from_value: 0,
                  to_value: nil,
                  per_unit_amount: "0.01",
                  flat_amount: "0.01"
                }
              ]
            }
          )
        end

        let(:billable_metric) { create(:sum_billable_metric, organization:) }

        before do
          create(
            :event,
            organization: subscription.organization,
            subscription:,
            code: billable_metric.code,
            timestamp: Time.zone.parse("2022-03-16"),
            properties: {item_id: -10}
          )
        end

        it "creates a fee with 0 units but expected amount details" do
          result = charge_subscription_service.call
          expect(result).to be_success
          expect(result.fees.first).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            charge_id: charge.id,
            amount_cents: 0,
            precise_amount_cents: 0.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: 0,
            unit_amount_cents: 0,
            precise_unit_amount: 0,
            events_count: 1,
            payment_status: "pending",
            amount_details: {
              "graduated_ranges" => [
                {
                  "flat_unit_amount" => "0.01",
                  "from_value" => 0,
                  "per_unit_amount" => "0.01",
                  "per_unit_total_amount" => "-0.1",
                  "to_value" => nil,
                  "total_with_flat_amount" => "-0.09",
                  "units" => "-10.0"
                }
              ]
            }
          )
        end
      end
    end

    context "with standard charge, all types of aggregation and presence of filter" do
      let(:region) do
        create(:billable_metric_filter, billable_metric:, key: "region", values: %w[europe usa])
      end

      let(:country) do
        create(:billable_metric_filter, billable_metric:, key: "country", values: %w[france])
      end

      let(:europe_filter) { create(:charge_filter, charge:, properties: {amount: "20"}) }
      let(:europe_filter_value) do
        create(:charge_filter_value, charge_filter: europe_filter, billable_metric_filter: region, values: ["europe"])
      end

      let(:usa_filter) { create(:charge_filter, charge:, properties: {amount: "50"}) }
      let(:usa_filter_value) do
        create(:charge_filter_value, charge_filter: usa_filter, billable_metric_filter: region, values: ["usa"])
      end

      let(:france_filter) { create(:charge_filter, charge:, properties: {amount: "10.12345"}) }
      let(:france_filter_value) do
        create(:charge_filter_value, charge_filter: france_filter, billable_metric_filter: country, values: ["france"])
      end

      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric:,
          properties: {amount: "10.12345"}
        )
      end

      before do
        europe_filter_value
        usa_filter_value
        france_filter_value

        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "usa", foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 10}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 5}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {country: "france", foo_bar: 5}
        )
      end

      it "creates expected fees for count_agg aggregation type" do
        billable_metric.update!(aggregation_type: :count_agg)
        result = charge_subscription_service.call
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(4)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: "EUR"
            )
          )
          expect(created_fees.first).to have_attributes(
            charge_filter: europe_filter,
            amount_cents: 4000,
            precise_amount_cents: 4000.0,
            taxes_precise_amount_cents: 0.0,
            units: 2,
            unit_amount_cents: 2000,
            precise_unit_amount: 20
          )

          expect(created_fees.second).to have_attributes(
            charge_filter: usa_filter,
            amount_cents: 5000,
            precise_amount_cents: 5000.0,
            taxes_precise_amount_cents: 0.0,
            units: 1,
            unit_amount_cents: 5000,
            precise_unit_amount: 50
          )

          expect(created_fees.third).to have_attributes(
            charge_filter: france_filter,
            amount_cents: 1012,
            precise_amount_cents: 1012.345,
            taxes_precise_amount_cents: 0.0,
            units: 1,
            unit_amount_cents: 1012,
            precise_unit_amount: 10.12345
          )
        end
      end

      it "creates expected fees for sum_agg aggregation type" do
        billable_metric.update!(aggregation_type: :sum_agg, field_name: "foo_bar")
        result = charge_subscription_service.call
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(4)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: "EUR"
            )
          )
          expect(created_fees.first).to have_attributes(
            charge_filter: europe_filter,
            amount_cents: 30_000,
            precise_amount_cents: 30_000.0,
            taxes_precise_amount_cents: 0.0,
            units: 15,
            unit_amount_cents: 2000,
            precise_unit_amount: 20
          )

          expect(created_fees.second).to have_attributes(
            charge_filter: usa_filter,
            amount_cents: 60_000,
            precise_amount_cents: 60_000.0,
            taxes_precise_amount_cents: 0.0,
            units: 12,
            unit_amount_cents: 5000,
            precise_unit_amount: 50
          )

          expect(created_fees.third).to have_attributes(
            charge_filter: france_filter,
            amount_cents: 5062,
            precise_amount_cents: 5061.725,
            taxes_precise_amount_cents: 0.0,
            units: 5,
            unit_amount_cents: 1012,
            precise_unit_amount: 10.12345
          )
        end
      end

      it "creates expected fees for max_agg aggregation type" do
        billable_metric.update!(aggregation_type: :max_agg, field_name: "foo_bar")
        result = charge_subscription_service.call
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(4)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: "EUR"
            )
          )
          expect(created_fees.first).to have_attributes(
            charge_filter: europe_filter,
            amount_cents: 20_000,
            precise_amount_cents: 20_000.0,
            taxes_precise_amount_cents: 0.0,
            units: 10,
            unit_amount_cents: 2000,
            precise_unit_amount: 20
          )

          expect(created_fees.second).to have_attributes(
            charge_filter: usa_filter,
            amount_cents: 60_000,
            precise_amount_cents: 60_000.0,
            taxes_precise_amount_cents: 0.0,
            units: 12,
            unit_amount_cents: 5000,
            precise_unit_amount: 50
          )

          expect(created_fees.third).to have_attributes(
            charge_filter: france_filter,
            amount_cents: 5062,
            precise_amount_cents: 5061.725,
            taxes_precise_amount_cents: 0.0,
            units: 5,
            unit_amount_cents: 1012,
            precise_unit_amount: 10.12345
          )
        end
      end

      context "when unique_count_agg" do
        it "creates expected fees for unique_count_agg aggregation type", transaction: false do
          billable_metric.update!(aggregation_type: :unique_count_agg, field_name: "foo_bar")
          result = charge_subscription_service.call
          expect(result).to be_success
          created_fees = result.fees

          aggregate_failures do
            expect(created_fees.count).to eq(4)
            expect(created_fees).to all(
              have_attributes(
                invoice_id: invoice.id,
                charge_id: charge.id,
                amount_currency: "EUR"
              )
            )
            expect(created_fees.first).to have_attributes(
              charge_filter: europe_filter,
              amount_cents: 4000,
              precise_amount_cents: 4_000.0,
              taxes_precise_amount_cents: 0.0,
              units: 2
            )

            expect(created_fees.second).to have_attributes(
              charge_filter: usa_filter,
              amount_cents: 5000,
              precise_amount_cents: 5_000.0,
              taxes_precise_amount_cents: 0.0,
              units: 1
            )

            expect(created_fees.third).to have_attributes(
              charge_filter: france_filter,
              amount_cents: 1012,
              precise_amount_cents: 1012.345,
              taxes_precise_amount_cents: 0.0,
              units: 1,
              unit_amount_cents: 1012,
              precise_unit_amount: 10.12345
            )
          end
        end
      end
    end

    context "with package charge and presence of filters" do
      let(:region) do
        create(:billable_metric_filter, billable_metric:, key: "region", values: %w[europe usa])
      end

      let(:country) do
        create(:billable_metric_filter, billable_metric:, key: "country", values: %w[france])
      end

      let(:europe_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {
            amount: "100",
            free_units: 1,
            package_size: 8
          }
        )
      end
      let(:europe_filter_value) do
        create(
          :charge_filter_value,
          charge_filter: europe_filter,
          billable_metric_filter: region,
          values: ["europe"]
        )
      end

      let(:usa_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {
            amount: "50",
            free_units: 0,
            package_size: 10
          }
        )
      end
      let(:usa_filter_value) do
        create(:charge_filter_value, charge_filter: usa_filter, billable_metric_filter: region, values: ["usa"])
      end

      let(:france_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {
            amount: "40",
            free_units: 1,
            package_size: 5
          }
        )
      end
      let(:france_filter_value) do
        create(
          :charge_filter_value,
          charge_filter: france_filter,
          billable_metric_filter: country,
          values: ["france"]
        )
      end

      let(:charge) do
        create(
          :package_charge,
          plan: subscription.plan,
          billable_metric:,
          properties: {
            amount: "0",
            free_units: 0,
            package_size: 1
          }
        )
      end

      before do
        europe_filter_value
        usa_filter_value
        france_filter_value

        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "usa", foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 10}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 5}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {country: "france", foo_bar: 5}
        )
      end

      it "creates expected fees for count_agg aggregation type" do
        billable_metric.update!(aggregation_type: :count_agg)
        result = charge_subscription_service.call
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(4)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: "EUR"
            )
          )
          expect(created_fees.first).to have_attributes(
            charge_filter: europe_filter,
            units: 2,
            amount_cents: 10_000,
            precise_amount_cents: 10_000.0,
            taxes_precise_amount_cents: 0.0,
            unit_amount_cents: 10_000,
            precise_unit_amount: 100
          )

          expect(created_fees.second).to have_attributes(
            charge_filter: usa_filter,
            amount_cents: 5000,
            precise_amount_cents: 5_000.0,
            taxes_precise_amount_cents: 0.0,
            units: 1,
            unit_amount_cents: 5000,
            precise_unit_amount: 50
          )

          expect(created_fees.third).to have_attributes(
            charge_filter: france_filter,
            amount_cents: 0,
            precise_amount_cents: 0.0,
            taxes_precise_amount_cents: 0.0,
            units: 1,
            unit_amount_cents: 0,
            precise_unit_amount: 0
          )
        end
      end
    end

    context "with percentage charge and presence of filters" do
      let(:region) do
        create(:billable_metric_filter, billable_metric:, key: "region", values: %w[europe usa])
      end

      let(:country) do
        create(:billable_metric_filter, billable_metric:, key: "country", values: %w[france])
      end

      let(:europe_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {rate: "2", fixed_amount: "1"}
        )
      end
      let(:europe_filter_value) do
        create(
          :charge_filter_value,
          charge_filter: europe_filter,
          billable_metric_filter: region,
          values: ["europe"]
        )
      end

      let(:usa_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {rate: "1", fixed_amount: "0"}
        )
      end
      let(:usa_filter_value) do
        create(:charge_filter_value, charge_filter: usa_filter, billable_metric_filter: region, values: ["usa"])
      end

      let(:france_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {rate: "5", fixed_amount: "1"}
        )
      end
      let(:france_filter_value) do
        create(
          :charge_filter_value,
          charge_filter: france_filter,
          billable_metric_filter: country,
          values: ["france"]
        )
      end

      let(:charge) do
        create(
          :percentage_charge,
          plan: subscription.plan,
          billable_metric:,
          properties: {rate: "0", fixed_amount: "0"}
        )
      end

      before do
        europe_filter_value
        usa_filter_value
        france_filter_value

        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "usa", foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 10}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 5}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {country: "france", foo_bar: 5}
        )
      end

      it "creates expected fees for count_agg aggregation type" do
        billable_metric.update!(aggregation_type: :count_agg)
        result = charge_subscription_service.call
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(4)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: "EUR"
            )
          )
          expect(created_fees.first).to have_attributes(
            charge_filter: europe_filter,
            amount_cents: 200 + 2 * 2,
            precise_amount_cents: 200.0 + 2 * 2,
            taxes_precise_amount_cents: 0.0,
            units: 2,
            unit_amount_cents: 102,
            precise_unit_amount: 1.02
          )

          expect(created_fees.second).to have_attributes(
            charge_filter: usa_filter,
            amount_cents: 1 * 1,
            precise_amount_cents: 1.0 * 1,
            taxes_precise_amount_cents: 0.0,
            units: 1,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01
          )

          expect(created_fees.third).to have_attributes(
            charge_filter: france_filter,
            amount_cents: 100 + 5 * 1,
            precise_amount_cents: 100.0 + 5.0 * 1,
            taxes_precise_amount_cents: 0.0,
            units: 1,
            unit_amount_cents: 105,
            precise_unit_amount: 1.05
          )
        end
      end
    end

    context "with graduated charge and presence of filters" do
      let(:region) do
        create(:billable_metric_filter, billable_metric:, key: "region", values: %w[europe usa])
      end

      let(:europe_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: nil,
                per_unit_amount: "0.01",
                flat_amount: "0.01"
              }
            ]
          }
        )
      end
      let(:europe_filter_value) do
        create(
          :charge_filter_value,
          charge_filter: europe_filter,
          billable_metric_filter: region,
          values: ["europe"]
        )
      end

      let(:usa_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: nil,
                per_unit_amount: "0.03",
                flat_amount: "0.01"
              }
            ]
          }
        )
      end
      let(:usa_filter_value) do
        create(:charge_filter_value, charge_filter: usa_filter, billable_metric_filter: region, values: ["usa"])
      end

      let(:charge) do
        create(
          :graduated_charge,
          plan: subscription.plan,
          billable_metric:,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: nil,
                per_unit_amount: "0",
                flat_amount: "0"
              }
            ]
          }
        )
      end

      before do
        europe_filter_value
        usa_filter_value

        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "usa", foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 10}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 5}
        )
      end

      context "without pricing unit on the charge" do
        it "creates expected fees for count_agg aggregation type" do
          billable_metric.update!(aggregation_type: :count_agg)
          result = charge_subscription_service.call
          expect(result).to be_success
          created_fees = result.fees

          expect(created_fees.count).to eq(3)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: "EUR"
            )
          )
          expect(created_fees.first).to have_attributes(
            charge_filter: europe_filter,
            amount_cents: 3,
            precise_amount_cents: 3.0,
            taxes_precise_amount_cents: 0.0,
            units: 2,
            unit_amount_cents: 1,
            precise_unit_amount: 0.015
          )

          expect(created_fees.second).to have_attributes(
            charge_filter: usa_filter,
            amount_cents: 4,
            precise_amount_cents: 4.0,
            taxes_precise_amount_cents: 0.0,
            units: 1,
            unit_amount_cents: 4,
            precise_unit_amount: 0.04
          )
        end

        it "does not create pricing unit usage" do
          expect { charge_subscription_service.call }.not_to change(PricingUnitUsage, :count)
        end
      end

      context "with pricing unit on the charge" do
        before do
          create(
            :applied_pricing_unit,
            organization: subscription.organization,
            conversion_rate: 2,
            pricing_unitable: charge
          )
        end

        it "creates expected fees for count_agg aggregation type" do
          billable_metric.update!(aggregation_type: :count_agg)
          result = charge_subscription_service.call
          expect(result).to be_success
          created_fees = result.fees

          expect(created_fees.count).to eq(3)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: "EUR"
            )
          )

          expect(created_fees.first).to have_attributes(
            charge_filter: europe_filter,
            amount_cents: 6,
            precise_amount_cents: 6.0,
            taxes_precise_amount_cents: 0.0,
            units: 2,
            unit_amount_cents: 2,
            precise_unit_amount: 0.02
          )

          expect(created_fees.first.pricing_unit_usage)
            .to be_persisted
            .and have_attributes(
              amount_cents: 3,
              precise_amount_cents: 3.0,
              unit_amount_cents: 1
            )

          expect(created_fees.second).to have_attributes(
            charge_filter: usa_filter,
            amount_cents: 8,
            precise_amount_cents: 8.0,
            taxes_precise_amount_cents: 0.0,
            units: 1,
            unit_amount_cents: 8,
            precise_unit_amount: 0.08
          )

          expect(created_fees.second.pricing_unit_usage)
            .to be_persisted
            .and have_attributes(
              amount_cents: 4,
              precise_amount_cents: 4.0,
              unit_amount_cents: 4
            )
        end
      end
    end

    context "with volume charge and presence of filters" do
      let(:region) do
        create(:billable_metric_filter, billable_metric:, key: "region", values: %w[europe usa])
      end

      let(:europe_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {
            volume_ranges: [
              {from_value: 0, to_value: nil, per_unit_amount: "2", flat_amount: "10"}
            ]
          }
        )
      end
      let(:europe_filter_value) do
        create(
          :charge_filter_value,
          charge_filter: europe_filter,
          billable_metric_filter: region,
          values: ["europe"]
        )
      end

      let(:usa_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {
            volume_ranges: [
              {from_value: 0, to_value: nil, per_unit_amount: "1", flat_amount: "10"}
            ]
          }
        )
      end
      let(:usa_filter_value) do
        create(:charge_filter_value, charge_filter: usa_filter, billable_metric_filter: region, values: ["usa"])
      end

      let(:charge) do
        create(
          :volume_charge,
          plan: subscription.plan,
          billable_metric:,
          properties: {
            volume_ranges: [
              {from_value: 0, to_value: nil, per_unit_amount: "0", flat_amount: "0"}
            ]
          }
        )
      end

      before do
        europe_filter_value
        usa_filter_value

        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "usa", foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 10}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 5}
        )
      end

      it "creates expected fees for count_agg aggregation type" do
        billable_metric.update!(aggregation_type: :count_agg)
        result = charge_subscription_service.call
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(3)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: "EUR"
            )
          )
          expect(created_fees.first).to have_attributes(
            charge_filter: europe_filter,
            amount_cents: 1400,
            precise_amount_cents: 1_400.0,
            taxes_precise_amount_cents: 0.0,
            units: 2,
            unit_amount_cents: 700,
            precise_unit_amount: 7
          )

          expect(created_fees.second).to have_attributes(
            charge_filter: usa_filter,
            amount_cents: 1100,
            precise_amount_cents: 1_100.0,
            taxes_precise_amount_cents: 0.0,
            units: 1,
            unit_amount_cents: 1100,
            precise_unit_amount: 11
          )
        end
      end
    end

    context "with graduated percentage charge and presence of filters" do
      let(:region) do
        create(:billable_metric_filter, billable_metric:, key: "region", values: %w[europe usa])
      end

      let(:europe_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {
            graduated_percentage_ranges: [
              {
                from_value: 0,
                to_value: nil,
                flat_amount: "0.01",
                rate: "2"
              }
            ]
          }
        )
      end
      let(:europe_filter_value) do
        create(
          :charge_filter_value,
          charge_filter: europe_filter,
          billable_metric_filter: region,
          values: ["europe"]
        )
      end

      let(:usa_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {
            graduated_percentage_ranges: [
              {
                from_value: 0,
                to_value: nil,
                flat_amount: "0.01",
                rate: "3"
              }
            ]
          }
        )
      end
      let(:usa_filter_value) do
        create(:charge_filter_value, charge_filter: usa_filter, billable_metric_filter: region, values: ["usa"])
      end

      let(:charge) do
        create(
          :graduated_percentage_charge,
          plan: subscription.plan,
          billable_metric:,
          properties: {
            graduated_percentage_ranges: [
              {
                from_value: 0,
                to_value: nil,
                flat_amount: "1",
                rate: "0"
              }
            ]
          }
        )
      end

      before do
        europe_filter_value
        usa_filter_value

        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "usa", foo_bar: 12}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 10}
        )
        create(
          :event,
          organization: subscription.organization,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: Time.zone.parse("2022-03-16"),
          properties: {region: "europe", foo_bar: 5}
        )
      end

      it "creates expected fees for count_agg aggregation type" do
        billable_metric.update!(aggregation_type: :count_agg)
        result = charge_subscription_service.call
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(3)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: "EUR"
            )
          )
          expect(created_fees.first).to have_attributes(
            charge_filter: europe_filter,
            amount_cents: 5, # 2 × 0.02 + 0.01
            precise_amount_cents: 5.0,
            taxes_precise_amount_cents: 0.0,
            units: 2,
            unit_amount_cents: 2,
            precise_unit_amount: 0.025
          )

          expect(created_fees.second).to have_attributes(
            charge_filter: usa_filter,
            amount_cents: 4, # 1 × 0.03 + 0.01
            precise_amount_cents: 4.0,
            taxes_precise_amount_cents: 0.0,
            units: 1,
            unit_amount_cents: 4,
            precise_unit_amount: 0.04
          )
        end
      end
    end

    context "with true-up fee and presence of filters" do
      let(:region) do
        create(:billable_metric_filter, billable_metric:, key: "region", values: %w[europe usa])
      end

      let(:europe_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {amount: "20"}
        )
      end
      let(:europe_filter_value) do
        create(
          :charge_filter_value,
          charge_filter: europe_filter,
          billable_metric_filter: region,
          values: ["europe"]
        )
      end

      let(:usa_filter) do
        create(
          :charge_filter,
          charge:,
          properties: {amount: "50"}
        )
      end
      let(:usa_filter_value) do
        create(:charge_filter_value, charge_filter: usa_filter, billable_metric_filter: region, values: ["usa"])
      end

      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric:,
          min_amount_cents: 1000,
          properties: {amount: "0"}
        )
      end

      before do
        europe_filter_value
        usa_filter_value
      end

      it "creates two fees" do
        travel_to(Time.zone.parse("2023-04-01")) do
          result = charge_subscription_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.fees.count).to eq(2)

            # 548 is 1000 prorated for 17 days.
            expect(result.fees.pluck(:amount_cents)).to contain_exactly(0, 548)
            expect(result.fees.pluck(:precise_amount_cents)).to contain_exactly(0, 548.3870967741935)
            expect(result.fees.pluck(:taxes_precise_amount_cents)).to contain_exactly(0.0, 0.0)
          end
        end
      end
    end

    context "with recurring weighted sum aggregation" do
      let(:context) { :recurring }
      let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }

      it "creates a fee and a cached aggregation" do
        result = charge_subscription_service.call
        expect(result).to be_success
        created_fee = result.fees.first
        cached_aggregation = result.cached_aggregations.first

        aggregate_failures do
          expect(created_fee.id).not_to be_nil
          expect(created_fee.invoice_id).to eq(invoice.id)
          expect(created_fee.charge_id).to eq(charge.id)
          expect(created_fee.amount_cents).to eq(0)
          expect(created_fee.precise_amount_cents).to eq(0.0)
          expect(created_fee.taxes_precise_amount_cents).to eq(0.0)
          expect(created_fee.amount_currency).to eq("EUR")
          expect(created_fee.units).to eq(0)
          expect(created_fee.total_aggregated_units).to eq(0)
          expect(created_fee.events_count).to eq(0)
          expect(created_fee.payment_status).to eq("pending")

          expect(cached_aggregation.id).not_to be_nil
          expect(cached_aggregation.organization).to eq(organization)
          expect(cached_aggregation.external_subscription_id).to eq(subscription.external_id)
          expect(cached_aggregation.charge_filter_id).to be_nil
          expect(cached_aggregation.charge_id).to eq(charge.id)
          expect(cached_aggregation.timestamp).to eq(boundaries.from_datetime)
          expect(cached_aggregation.current_aggregation).to eq(0.0)
        end
      end
    end

    context "with aggregation error" do
      let(:billable_metric) do
        create(
          :billable_metric,
          aggregation_type: "max_agg",
          field_name: "foo_bar"
        )
      end
      let(:aggregator_service) { instance_double(BillableMetrics::Aggregations::MaxService) }
      let(:error_result) do
        BaseService::Result.new.service_failure!(code: "aggregation_failure", message: "Test message")
      end

      it "returns an error" do
        allow(BillableMetrics::Aggregations::MaxService).to receive(:new)
          .and_return(aggregator_service)
        allow(aggregator_service).to receive(:aggregate)
          .and_return(error_result)

        result = charge_subscription_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("aggregation_failure")
        expect(result.error.error_message).to eq("Test message")

        expect(BillableMetrics::Aggregations::MaxService).to have_received(:new)
        expect(aggregator_service).to have_received(:aggregate)
      end
    end

    context "when current usage" do
      let(:context) { :current_usage }

      context "with all types of aggregation" do
        BillableMetric::AGGREGATION_TYPES.keys.each do |aggregation_type|
          before do
            billable_metric.update!(
              aggregation_type:,
              field_name: "foo_bar",
              weighted_interval: "seconds",
              custom_aggregator: "def aggregate(event, agg, aggregation_properties); agg; end"
            )

            charge.update!(min_amount_cents: 1000)
          end

          it "initializes fees" do
            result = charge_subscription_service.call

            expect(result).to be_success

            usage_fee = result.fees.first

            aggregate_failures do
              expect(result.fees.count).to eq(1)
              expect(usage_fee.id).to be_nil
              expect(usage_fee.invoice_id).to eq(invoice.id)
              expect(usage_fee.charge_id).to eq(charge.id)
              expect(usage_fee.amount_cents).to eq(0)
              expect(usage_fee.precise_amount_cents).to eq(0.0)
              expect(usage_fee.taxes_precise_amount_cents).to eq(0.0)
              expect(usage_fee.amount_currency).to eq("EUR")
              expect(usage_fee.units).to eq(0)
            end
          end
        end
      end

      context "with graduated charge model" do
        let(:charge) do
          create(
            :graduated_charge,
            plan: subscription.plan,
            charge_model: "graduated",
            billable_metric:,
            properties: {
              graduated_ranges: [
                {
                  from_value: 0,
                  to_value: nil,
                  per_unit_amount: "0.01",
                  flat_amount: "0.01"
                }
              ]
            }
          )
        end

        before do
          create_list(
            :event,
            4,
            organization: subscription.organization,
            subscription:,
            code: charge.billable_metric.code,
            timestamp: Time.zone.parse("2022-03-16")
          )
        end

        it "initialize a fee" do
          result = charge_subscription_service.call

          expect(result).to be_success

          usage_fee = result.fees.first

          aggregate_failures do
            expect(usage_fee.id).to be_nil
            expect(usage_fee.invoice_id).to eq(invoice.id)
            expect(usage_fee.charge_id).to eq(charge.id)
            expect(usage_fee.amount_cents).to eq(5)
            expect(usage_fee.precise_amount_cents).to eq(5.0)
            expect(usage_fee.taxes_precise_amount_cents).to eq(0.0)
            expect(usage_fee.amount_currency).to eq("EUR")
            expect(usage_fee.units.to_s).to eq("4.0")
          end
        end
      end

      context "with aggregation error" do
        let(:billable_metric) do
          create(
            :billable_metric,
            aggregation_type: "max_agg",
            field_name: "foo_bar"
          )
        end
        let(:aggregator_service) { instance_double(BillableMetrics::Aggregations::MaxService) }
        let(:error_result) do
          BaseService::Result.new.service_failure!(code: "aggregation_failure", message: "Test message")
        end

        it "returns an error" do
          allow(BillableMetrics::Aggregations::MaxService).to receive(:new)
            .and_return(aggregator_service)
          allow(aggregator_service).to receive(:aggregate)
            .and_return(error_result)

          result = charge_subscription_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq("aggregation_failure")
          expect(result.error.error_message).to eq("Test message")

          expect(BillableMetrics::Aggregations::MaxService).to have_received(:new)
          expect(aggregator_service).to have_received(:aggregate)
        end
      end
    end

    context "when apply taxes" do
      let(:apply_taxes) { true }

      before do
        create(:tax, :applied_to_billing_entity, organization:, rate: 20)

        create(
          :event,
          organization: invoice.organization,
          subscription:,
          code: billable_metric.code,
          timestamp: boundaries.charges_to_datetime - 2.days
        )
      end

      it "creates a fee with applied taxes" do
        result = charge_subscription_service.call
        expect(result).to be_success
        expect(result.fees.first).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          charge_id: charge.id,
          amount_cents: 2000,
          precise_amount_cents: 2000.0,
          amount_currency: "EUR",
          units: 1,
          unit_amount_cents: 2000,
          precise_unit_amount: 20.0,
          events_count: 1,
          payment_status: "pending",

          taxes_rate: 20.0,
          taxes_amount_cents: 400,
          taxes_precise_amount_cents: 400.0
        )
        expect(result.fees.first.applied_taxes.count).to eq(1)
      end
    end
  end
end
