# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::ApplyPayInAdvanceChargeModelService do
  let(:charge_service) { described_class.new(metered_item:, aggregation_result:, properties:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, :pay_in_advance, plan:) }
  let(:subscription) { create(:subscription, plan:) }
  let(:metered_item) do
    Fees::ChargeService::MeteredItem.from_charge(
      charge:,
      boundaries: BillingPeriodBoundaries.new(
        from_datetime: subscription.started_at,
        to_datetime: subscription.started_at.end_of_month,
        charges_from_datetime: subscription.started_at,
        charges_to_datetime: subscription.started_at.end_of_month,
        charges_duration: subscription.started_at.end_of_month.day - subscription.started_at.day + 1,
        timestamp: subscription.started_at.end_of_month
      )
    )
  end

  let(:aggregation_result) do
    BillableMetrics::Aggregations::BaseService::Result.new.tap do |result|
      result.aggregation = 10
      result.pay_in_advance_aggregation = 1
      result.count = 5
      result.options = {}
      result.aggregator = aggregator
      result.pay_in_advance_event = pay_in_advance_event
    end
  end
  let(:properties) { {} }

  let(:billing_context) { Billing::Context.from(subscription:) }

  let(:aggregator) do
    BillableMetrics::Aggregations::CountService.new(
      event_store: Events::Stores::PostgresStore.new(billing_context:, boundaries: nil),
      metered_item:,
      billing_context:,
      boundaries: nil
    )
  end

  let(:pay_in_advance_event) do
    source = create(
      :event,
      external_subscription_id: subscription.external_id,
      external_customer_id: subscription.external_id,
      organization_id: organization.id,
      properties: {}
    )
    Events::CommonFactory.new_instance(source:)
  end

  describe "#call" do
    context "when charge is not pay_in_advance" do
      let(:charge) { create(:standard_charge) }

      it "returns an error" do
        result = charge_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("apply_charge_model_error")
        expect(result.error.error_message).to eq("Charge is not pay_in_advance")
      end
    end

    shared_examples "a charge model" do
      it "delegates to the charge model service" do
        previous_agg_result = BillableMetrics::Aggregations::BaseService::Result.new.tap do |result|
          result.aggregation = 9
          result.count = 4
          result.options = {}
          result.aggregator = aggregator
          result.pay_in_advance_event = pay_in_advance_event
        end

        allow(charge_model_class).to receive(:apply) do |pricing_structure:, **|
          charge_model_class::Result.new.tap do |r|
            r.amount = pricing_structure.properties[:exclude_event] ? 8 : 10
          end
        end

        result = charge_service.call

        expect(result.units).to eq(1)
        expect(result.count).to eq(1)
        expect(result.amount).to eq(200) # In cents
        expect(result.precise_amount).to eq(200.0) # In cents
        expect(result.unit_amount).to eq(2)

        expect(charge_model_class).to have_received(:apply).with(
          pricing_structure: ChargeModels::PricingStructure.from_charge(charge).with(properties:),
          aggregation_result:
        )
        expect(charge_model_class).to have_received(:apply).with(
          pricing_structure: ChargeModels::PricingStructure.from_charge(charge).with(
            properties: properties.merge(exclude_event: true)
          ),
          aggregation_result: have_attributes(
            aggregation: previous_agg_result.aggregation,
            count: previous_agg_result.count,
            options: previous_agg_result.options,
            aggregator: previous_agg_result.aggregator,
            pay_in_advance_event: previous_agg_result.pay_in_advance_event
          )
        )
      end

      context "when the event is not persisted" do
        before { pay_in_advance_event.persisted = false }

        it "delegates to the charge model service" do
          non_persisted_agg_result = BillableMetrics::Aggregations::BaseService::Result.new.tap do |result|
            result.aggregation = 11
            result.count = 6
            result.options = {}
            result.aggregator = aggregator
            result.pay_in_advance_event = pay_in_advance_event
          end

          allow(charge_model_class).to receive(:apply) do |pricing_structure:, **|
            charge_model_class::Result.new.tap do |r|
              r.amount = pricing_structure.properties[:include_event_value] ? 10 : 8
            end
          end

          result = charge_service.call

          expect(result.units).to eq(1)
          expect(result.count).to eq(1)
          expect(result.amount).to eq(2_00) # In cents
          expect(result.precise_amount).to eq(2_00.0) # In cents
          expect(result.unit_amount).to eq(2)
          expect(result.amount_details).to be_nil

          expect(charge_model_class).to have_received(:apply).with(
            pricing_structure: ChargeModels::PricingStructure.from_charge(charge).with(properties:),
            aggregation_result:
          )
          expect(charge_model_class).to have_received(:apply).with(
            pricing_structure: ChargeModels::PricingStructure.from_charge(charge).with(
              properties: properties.merge(include_event_value: true)
            ),
            aggregation_result: have_attributes(
              aggregation: non_persisted_agg_result.aggregation,
              count: non_persisted_agg_result.count,
              options: non_persisted_agg_result.options,
              aggregator: non_persisted_agg_result.aggregator,
              pay_in_advance_event: non_persisted_agg_result.pay_in_advance_event
            )
          )
        end
      end
    end

    describe "when standard charge model" do
      let(:charge_model_class) { ChargeModels::StandardService }

      it_behaves_like "a charge model"
    end

    describe "when graduated charge model" do
      let(:charge) do
        create(
          :graduated_charge,
          :pay_in_advance,
          plan:,
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
      let(:charge_model_class) { ChargeModels::GraduatedService }

      it_behaves_like "a charge model"
    end

    describe "when package charge model" do
      let(:charge) { create(:package_charge, :pay_in_advance, plan:) }
      let(:charge_model_class) { ChargeModels::PackageService }

      it_behaves_like "a charge model"
    end

    context "when the metered item is backed by a billing segment" do
      let(:customer) { create(:customer, organization:) }
      let(:contract) { create(:contract, organization:, customer:) }
      let(:billable_metric) { create(:billable_metric, organization:) }
      let(:product) { create(:product, :metered, organization:, billable_metric:) }
      let(:rate_card) { create(:rate_card, :advance, organization:, product:) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
      let(:billing_segment) do
        create(
          :billing_segment,
          organization:,
          customer:,
          contract:,
          contract_rate_card:,
          currency: "EUR",
          rate_properties: {"amount" => "2"}
        )
      end
      let(:metered_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:) }
      let(:charge_model_result) do
        ChargeModels::StandardService::Result.new.tap do |result|
          result.amount = 10
        end
      end

      before do
        allow(ChargeModels::StandardService).to receive(:apply).and_return(charge_model_result)
      end

      it "applies the billing segment pricing structure" do
        result = charge_service.call

        expect(result).to be_success
        expect(ChargeModels::StandardService).to have_received(:apply).with(
          pricing_structure: ChargeModels::PricingStructure.from_billing_segment(billing_segment).with(properties:),
          aggregation_result:
        )
      end
    end

    describe "when percentage charge model" do
      let(:charge) { create(:percentage_charge, :pay_in_advance, plan:) }
      let(:charge_model_class) { ChargeModels::PercentageService }

      it_behaves_like "a charge model"

      context "when a unique-count event does not add a unit" do
        let(:charge) do
          create(:percentage_charge, :pay_in_advance, plan:, billable_metric: create(:unique_count_billable_metric, organization:))
        end
        let(:aggregator) do
          BillableMetrics::Aggregations::UniqueCountService.new(
            event_store: Events::Stores::PostgresStore.new(billing_context:, boundaries: nil),
            metered_item:,
            billing_context:,
            boundaries: nil
          )
        end
        let(:aggregation_result) do
          super().tap { |result| result.pay_in_advance_aggregation = 0 }
        end
        let(:amount_details) do
          {
            rate: "10",
            fixed_fee_unit_amount: "0",
            units: "0",
            free_units: "0",
            paid_units: "0",
            free_events: "0",
            paid_events: "0",
            fixed_fee_total_amount: "0",
            min_max_adjustment_total_amount: "0",
            per_unit_total_amount: "0"
          }
        end

        before do
          allow(charge_model_class).to receive(:apply) do
            charge_model_class::Result.new.tap do |result|
              result.amount = 0
              result.amount_details = amount_details
            end
          end
        end

        it "keeps zero-unit fixed-fee details finite and zero" do
          result = charge_service.call

          expect(result.units).to eq(0)
          expect(result.amount).to eq(0)
          expect(result.unit_amount).to eq(BigDecimal(0))
          expect(result.unit_amount.finite?).to be(true)
          expect(result.amount_details[:fixed_fee_total_amount]).to eq("0.0")
          expect(result.amount_details[:units]).to eq("0.0")
          expect(charge_model_class).to have_received(:apply).with(
            pricing_structure: anything,
            aggregation_result: have_attributes(count: aggregation_result.count)
          ).twice
        end

        context "when pricing returns a nonzero amount despite zero units" do
          before do
            allow(charge_model_class).to receive(:apply) do |pricing_structure:, **|
              charge_model_class::Result.new.tap do |result|
                result.amount = pricing_structure.properties[:exclude_event] ? 0 : BigDecimal("0.3")
                result.amount_details = amount_details.merge(
                  fixed_fee_unit_amount: "0.3",
                  fixed_fee_total_amount: pricing_structure.properties[:exclude_event] ? "0" : "0.3"
                )
              end
            end
          end

          it "returns the nonzero amount with a finite zero unit amount" do
            result = charge_service.call

            expect(result.amount).to eq(30)
            expect(result.units).to eq(0)
            expect(result.unit_amount).to eq(BigDecimal(0))
            expect(result.unit_amount.finite?).to be(true)
            expect(result.amount_details[:fixed_fee_unit_amount]).to eq("0.3")
            expect(result.amount_details[:fixed_fee_total_amount]).to eq("0.3")
          end
        end

        context "when the event is not persisted" do
          before { pay_in_advance_event.persisted = false }

          it "does not adjust the count when estimating the event" do
            charge_service.call

            expect(charge_model_class).to have_received(:apply).with(
              pricing_structure: anything,
              aggregation_result: have_attributes(count: aggregation_result.count)
            ).twice
          end
        end

        context "when the event adds a unique unit" do
          let(:aggregation_result) do
            super().tap { |result| result.pay_in_advance_aggregation = 1 }
          end

          it "adjusts the count by the new unique unit" do
            charge_service.call

            expect(charge_model_class).to have_received(:apply).with(
              pricing_structure: anything,
              aggregation_result: have_attributes(count: aggregation_result.count - 1)
            )
          end

          context "when the event is not persisted" do
            before { pay_in_advance_event.persisted = false }

            it "adjusts the count by the new unique unit" do
              charge_service.call

              expect(charge_model_class).to have_received(:apply).with(
                pricing_structure: anything,
                aggregation_result: have_attributes(count: aggregation_result.count + 1)
              )
            end
          end
        end
      end

      context "when a sum event has multiple units" do
        let(:charge) do
          create(:percentage_charge, :pay_in_advance, plan:, billable_metric: create(:sum_billable_metric, organization:))
        end
        let(:aggregator) do
          BillableMetrics::Aggregations::SumService.new(
            event_store: Events::Stores::PostgresStore.new(billing_context:, boundaries: nil),
            metered_item:,
            billing_context:,
            boundaries: nil
          )
        end
        let(:aggregation_result) do
          super().tap { |result| result.pay_in_advance_aggregation = 3 }
        end

        before do
          allow(charge_model_class).to receive(:apply) do
            charge_model_class::Result.new.tap { |result| result.amount = 1 }
          end
        end

        it "adjusts the persisted-event count by one" do
          charge_service.call

          expect(charge_model_class).to have_received(:apply).with(
            pricing_structure: anything,
            aggregation_result: have_attributes(count: aggregation_result.count - 1)
          )
        end

        context "when the event is not persisted" do
          before { pay_in_advance_event.persisted = false }

          it "adjusts the estimated-event count by one" do
            charge_service.call

            expect(charge_model_class).to have_received(:apply).with(
              pricing_structure: anything,
              aggregation_result: have_attributes(count: aggregation_result.count + 1)
            )
          end
        end

        context "when the event has zero units" do
          let(:aggregation_result) do
            super().tap { |result| result.pay_in_advance_aggregation = 0 }
          end

          before do
            allow(charge_model_class).to receive(:apply) do |pricing_structure:, **|
              charge_model_class::Result.new.tap do |result|
                result.amount = pricing_structure.properties[:exclude_event] ? 0 : BigDecimal("0.3")
                result.amount_details = {
                  rate: "10",
                  fixed_fee_unit_amount: "0.3",
                  units: "0",
                  free_units: "0",
                  paid_units: "0",
                  free_events: "0",
                  paid_events: "0",
                  fixed_fee_total_amount: pricing_structure.properties[:exclude_event] ? "0" : "0.3",
                  min_max_adjustment_total_amount: "0",
                  per_unit_total_amount: "0"
                }
              end
            end
          end

          it "retains the fixed fee and keeps its zero-unit amount finite" do
            result = charge_service.call

            expect(result.amount).to eq(30)
            expect(result.units).to eq(0)
            expect(result.unit_amount).to eq(BigDecimal(0))
            expect(result.unit_amount.finite?).to be(true)
            expect(result.amount_details[:fixed_fee_unit_amount]).to eq("0.3")
            expect(result.amount_details[:fixed_fee_total_amount]).to eq("0.3")
            expect(charge_model_class).to have_received(:apply).with(
              pricing_structure: anything,
              aggregation_result: have_attributes(count: aggregation_result.count - 1)
            )
          end

          context "when the event is not persisted" do
            before { pay_in_advance_event.persisted = false }

            it "adjusts the estimated-event count by one" do
              charge_service.call

              expect(charge_model_class).to have_received(:apply).with(
                pricing_structure: anything,
                aggregation_result: have_attributes(count: aggregation_result.count + 1)
              )
            end
          end
        end
      end
    end

    describe "when graduated percentage charge model", :premium do
      let(:charge) do
        create(
          :graduated_percentage_charge,
          :pay_in_advance,
          plan:,
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

      let(:charge_model_class) { ChargeModels::GraduatedPercentageService }

      it_behaves_like "a charge model"
    end

    describe "when dynamic charge model" do
      let(:charge) { create(:dynamic_charge, :pay_in_advance, plan:) }
      let(:charge_model_class) { ChargeModels::DynamicService }
      let(:subscription) { create(:subscription, organization:, plan:) }

      let(:aggregator) do
        BillableMetrics::Aggregations::SumService.new(
          event_store: Events::Stores::PostgresStore.new(billing_context:, boundaries: nil),
          metered_item:,
          billing_context:,
          boundaries: nil
        )
      end

      it_behaves_like "a charge model"
    end
  end
end
