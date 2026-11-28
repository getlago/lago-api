# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::CreatePayInAdvanceService do
  subject(:fee_service) { described_class.new(metered_item:, billing_context:, billing_at:, estimate:) }

  let(:billing_entity) { create(:billing_entity) }
  let(:organization) { billing_entity.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:billing_context) { Billing::Context.from(subscription:) }
  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }
  let(:estimate) { false }

  let(:charge_filter) { nil }

  # The default metric is count_agg, so each event counts as one unit priced at 0.10 EUR.
  let(:charge) { create(:standard_charge, :pay_in_advance, billable_metric:, plan:, properties: {"amount" => "0.10"}) }

  let(:event) do
    source = create(
      :event,
      external_subscription_id: subscription.external_id,
      external_customer_id: customer.external_id,
      organization_id: organization.id,
      code: billable_metric.code,
      properties: event_properties
    )
    Events::CommonFactory.new_instance(source:)
  end

  let(:event_properties) { {} }
  let(:billing_at) { event.timestamp }
  let(:date_service) do
    Subscriptions::DatesService.new_instance(
      subscription,
      billing_at,
      current_usage: true
    )
  end
  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: date_service.from_datetime,
      to_datetime: date_service.to_datetime,
      charges_from_datetime: date_service.charges_from_datetime,
      charges_to_datetime: date_service.charges_to_datetime,
      charges_duration: date_service.charges_duration_in_days,
      timestamp: billing_at
    )
  end
  let(:metered_item) do
    Fees::ChargeService::MeteredItem.from_charge(
      charge:,
      boundaries:,
      charge_filter: charge_filter,
      event:
    )
  end

  before { tax }

  describe "#call" do
    context "when the metered item is backed by a billing segment" do
      let(:contract) { create(:contract, organization:, customer:) }
      let(:product) { create(:product, :metered, organization:, billable_metric:) }
      let(:rate_card) { create(:rate_card, :advance, organization:, product:, display_on_invoice: false) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
      # The segment spans Time.current.beginning_of_day to one month later, so events at Time.current fall inside it.
      let(:billing_segment) do
        create(
          :billing_segment,
          organization:,
          customer:,
          contract:,
          contract_rate_card:,
          currency: "EUR",
          rate_properties: {"amount" => "10"}
        )
      end
      let(:event) do
        source = create(
          :event,
          external_subscription_id: contract.external_id,
          external_customer_id: customer.external_id,
          organization_id: organization.id,
          code: billable_metric.code,
          properties: event_properties
        )
        Events::CommonFactory.new_instance(source:)
      end
      let(:metered_item) do
        Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:, event:)
      end
      let(:billing_context) { Billing::Context.from(contract:) }

      it "creates a product fee without a subscription or legacy charge" do
        result = fee_service.call

        expect(result).to be_success
        expect(result.fees.sole).to have_attributes(
          subscription: nil,
          charge: nil,
          organization_id: organization.id,
          billing_entity_id: billing_entity.id,
          amount_currency: "EUR",
          fee_type: "product",
          invoiceable: product,
          contract:,
          contract_rate_card:,
          rate_card_rate: billing_segment.rate_card_rate,
          rate_override: billing_segment.rate_override,
          units: 1, # count_agg: the one event of the segment
          events_count: 1,
          amount_cents: 1000, # 1 unit * 10 EUR * 100
          precise_amount_cents: 1000.0, # 1 unit * 10 EUR * 100
          unit_amount_cents: 1000, # 1000 cents / 1 unit
          precise_unit_amount: 10.0, # 10 EUR / 1 unit
          taxes_rate: 20.0,
          taxes_amount_cents: 200, # 1000 cents * 20%
          taxes_precise_amount_cents: 200.0 # 1000 cents * 20%
        )
        expect(result.fees.sole.applied_taxes.sole).to have_attributes(
          tax:, tax_rate: 20.0, amount_cents: 200 # non-invoiceable fee: 20% of 1000 cents applied at creation
        )
        expect(result.fees.sole.properties).to include(
          "from_datetime" => billing_segment.started_at.iso8601(6),
          "to_datetime" => billing_segment.ended_at.iso8601(6),
          "charges_from_datetime" => billing_segment.started_at.iso8601(6),
          "charges_to_datetime" => billing_segment.ended_at.iso8601(6)
        )
      end

      context "with a legacy charge linked to the product" do
        let(:product) { create(:product, :metered, organization:, billable_metric:, charge:) }

        it "persists the product fee without its legacy charge" do
          expect(fee_service.call.fees.sole.reload).to have_attributes(
            fee_type: "product", charge_id: nil, contract_rate_card:,
            units: 1, # count_agg: the one event of the segment
            amount_cents: 1000, # 1 unit * 10 EUR of the rate card, not the 0.10 EUR of the legacy charge
            precise_amount_cents: 1000.0,
            taxes_amount_cents: 200 # 1000 cents * 20%
          )
        end
      end

      context "with aggregation state" do
        let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }
        let(:event_properties) { {"value" => "-3"} }
        let(:earlier_event) do
          create(
            :event,
            external_subscription_id: contract.external_id,
            external_customer_id: customer.external_id,
            organization_id: organization.id,
            code: billable_metric.code,
            timestamp: billing_segment.started_at,
            properties: {"value" => "10"}
          )
        end
        let(:seeded_aggregation) do
          create(
            :cached_aggregation,
            organization:,
            charge: nil,
            contract:,
            product:,
            product_filter: nil,
            external_subscription_id: contract.external_id,
            event_transaction_id: earlier_event.transaction_id,
            timestamp: billing_segment.started_at,
            grouped_by: {},
            current_aggregation: 10, # the earlier event's value
            max_aggregation: 10 # billed when the earlier event was priced
          )
        end
        let(:new_aggregations) { CachedAggregation.where(contract:, product:, event_transaction_id: event.transaction_id) }

        before { seeded_aggregation }

        it "persists the decrease and billed maximum with the fee" do
          result = fee_service.call

          expect(result).to be_success
          expect(new_aggregations.sole).to have_attributes(
            charge_id: nil, product_filter_id: nil,
            current_aggregation: 7, # 10 seeded - 3 of the event
            max_aggregation: 10, # 7 < 10, so the billed maximum is kept
            external_subscription_id: contract.external_id, event_transaction_id: event.transaction_id
          )
          expect(result.fees.sole).to have_attributes(
            units: 0, # the -3 applied is negative, so no unit is shown
            amount_cents: 0, # 7 stays below the billed maximum of 10, nothing more to bill
            precise_amount_cents: 0.0,
            taxes_amount_cents: 0 # 0 cents * 20%
          )
        end

        context "when the event raises the total above the billed maximum" do
          let(:event_properties) { {"value" => "5"} }

          it "bills only the units above the billed maximum" do
            result = fee_service.call

            expect(new_aggregations.sole).to have_attributes(
              current_aggregation: 15, # 10 seeded + 5 of the event
              max_aggregation: 15 # 15 > 10, the new maximum
            )
            expect(result.fees.sole).to have_attributes(
              units: 5, # 15 - 10 billed maximum
              amount_cents: 5000, # 5 units * 10 EUR * 100
              precise_amount_cents: 5000.0,
              taxes_amount_cents: 1000 # 5000 cents * 20%
            )
          end
        end

        it "rolls back the snapshot when retrying an already billed event" do
          expect { fee_service.call }.to change(CachedAggregation, :count).by(1)

          retry_result = nil
          expect { retry_result = fee_service.call }.to not_change(CachedAggregation, :count)
            .and not_change(Fee, :count)
          expect(retry_result.error.messages).to eq(pay_in_advance_event_transaction_id: ["pay_in_advance_fee_already_exists"])
        end

        context "when estimating" do
          let(:estimate) { true }

          it "persists the snapshot when the same call is not an estimate" do
            expect { described_class.call(metered_item:, billing_context:, billing_at:, estimate: false) }
              .to change(CachedAggregation, :count).by(1)
              .and change(Fee, :count).by(1)
          end

          it "leaves both billing state and fees untouched" do
            expect { fee_service.call }.to not_change(CachedAggregation, :count)
              .and not_change(Fee, :count)
          end

          it "returns unsaved aggregation state for the invoice transaction" do
            expect(fee_service.call.cached_aggregations.sole).to have_attributes(
              new_record?: true,
              current_aggregation: 7, # 10 seeded - 3 of the event
              max_aggregation: 10 # 7 < 10, so the billed maximum is kept
            )
          end
        end

        context "when saving the fee fails" do
          it "persists the snapshot when taxes are applied" do
            expect { fee_service.call }.to change(new_aggregations, :count).from(0).to(1)
            expect(Fee.where(pay_in_advance_event_transaction_id: event.transaction_id).sole).to have_attributes(
              amount_cents: 0, # 7 stays below the billed maximum of 10, nothing more to bill
              taxes_amount_cents: 0 # 0 cents * 20%
            )
          end

          context "with a tax failure" do
            before do
              allow(Fees::ApplyTaxesService).to receive(:call!).and_raise("tax failure")
            end

            it "rolls back the snapshot so a retry starts from the same state" do
              expect { fee_service.call }.to raise_error("tax failure")
              expect(new_aggregations).to be_empty
              expect(CachedAggregation.where(contract:, product:).sole).to eq(seeded_aggregation)
              expect(Fee.where(pay_in_advance_event_transaction_id: event.transaction_id)).to be_empty
              expect(Fee::AppliedTax.count).to eq(0)
            end
          end
        end
      end

      context "with a legacy add-on linked to the product" do
        let(:add_on) { create(:add_on, organization:) }
        let(:product) { create(:product, :metered, organization:, billable_metric:, add_on:) }

        it "keeps the product fee distinct from a one-off add-on fee" do
          expect(fee_service.call.fees.sole.reload).to have_attributes(
            fee_type: "product", add_on_id: nil, charge_id: nil, contract_rate_card:,
            units: 1, # count_agg: the one event of the segment
            amount_cents: 1000, # 1 unit * 10 EUR * 100
            precise_amount_cents: 1000.0
          )
        end
      end

      it "does not persist another product fee on retry" do
        fee_service.call
        result = nil

        expect { result = fee_service.call }.not_to change(Fee, :count)
        expect(result).not_to be_success
        expect(result.error.messages).to eq(pay_in_advance_event_transaction_id: ["pay_in_advance_fee_already_exists"])
        expect(Fee.where(pay_in_advance_event_transaction_id: event.transaction_id).sole).to have_attributes(
          amount_cents: 1000, # 1 unit * 10 EUR, from the first call only
          units: 1
        )
      end

      context "when the card uses a product filter" do
        let(:metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
        let(:product_filter) { create(:product_filter, organization:, product:) }
        let(:rate_card) { create(:rate_card, :advance, organization:, product:, product_filter:, display_on_invoice: false) }
        let(:event_properties) { {"region" => "eu"} }
        # Only the first unit of the period is priced, so the fee shows which events the filter counts.
        let(:rate_card_rate) do
          create(
            :rate_card_rate,
            organization:,
            rate_card:,
            rate_model: "graduated",
            rate_properties: {
              "graduated_ranges" => [
                {"from_value" => 0, "to_value" => 1, "per_unit_amount" => "10", "flat_amount" => "0"},
                {"from_value" => 2, "to_value" => nil, "per_unit_amount" => "0", "flat_amount" => "0"}
              ]
            }
          )
        end
        let(:billing_segment) do
          create(
            :billing_segment,
            organization:,
            customer:,
            contract:,
            contract_rate_card:,
            rate_card_rate:,
            currency: "EUR",
            rate_properties: rate_card_rate.rate_properties
          )
        end
        # An earlier event outside the filter: counted, it would make the "eu" event the free second unit.
        let(:us_event) do
          create(
            :event,
            external_subscription_id: contract.external_id,
            external_customer_id: customer.external_id,
            organization_id: organization.id,
            code: billable_metric.code,
            timestamp: billing_segment.started_at,
            properties: {"region" => "us"}
          )
        end

        before do
          create(:product_filter_value, organization:, product_filter:, billable_metric_filter: metric_filter, value: "eu")
          us_event
        end

        it "stores the selected filter values on the fee" do
          fee = fee_service.call.fees.sole

          expect(fee.reload.properties["product_filter_values"]).to eq("region" => ["eu"])
          expect(fee).to have_attributes(
            units: 1, # count_agg: the "eu" event, the "us" one is left out by the filter
            events_count: 1,
            # graduated model(1) - model(0) = 1 * 10 EUR * 100 - 0; with the "us" event counted it would be
            # model(2) - model(1) = 1000 - 1000 = 0
            amount_cents: 1000,
            precise_amount_cents: 1000.0,
            taxes_amount_cents: 200 # 1000 cents * 20%
          )
        end

        it "returns a validation failure on retry for a filtered fee" do
          fee = fee_service.call.fees.sole
          retry_result = fee_service.call

          expect(fee.product_filter).to eq(product_filter)
          expect(retry_result).not_to be_success
          expect(retry_result.error.messages).to eq(pay_in_advance_event_transaction_id: ["pay_in_advance_fee_already_exists"])
          expect(Fee.where(pay_in_advance_event_transaction_id: event.transaction_id).count).to eq(1)
        end
      end

      context "when two products share the metric" do
        let(:other_product) { create(:product, :metered, organization:, billable_metric:) }
        let(:other_rate_card) { create(:rate_card, :advance, organization:, product: other_product, display_on_invoice: false) }
        let(:other_contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card) }
        let(:other_billing_segment) do
          create(
            :billing_segment,
            organization:,
            customer:,
            contract:,
            contract_rate_card: other_contract_rate_card,
            currency: "EUR",
            rate_properties: {"amount" => "4"}
          )
        end
        let(:other_metered_item) do
          Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: other_billing_segment, event:)
        end
        let(:other_fee_service) { described_class.new(metered_item: other_metered_item, billing_context:) }

        it "persists one fee for each contract rate card" do
          first = fee_service.call.fees.sole
          second = other_fee_service.call.fees.sole

          expect([first.contract_rate_card_id, second.contract_rate_card_id])
            .to eq([contract_rate_card.id, other_contract_rate_card.id])
          expect(Fee.where(pay_in_advance_event_transaction_id: event.transaction_id).count).to eq(2)
          expect(first).to have_attributes(units: 1, amount_cents: 1000) # 1 unit * 10 EUR * 100
          expect(second).to have_attributes(units: 1, amount_cents: 400) # 1 unit * 4 EUR * 100
        end
      end

      context "when a different transaction uses the same card" do
        let(:other_event) do
          Events::CommonFactory.new_instance(source: create(
            :event,
            external_subscription_id: contract.external_id,
            external_customer_id: customer.external_id,
            organization_id: organization.id,
            code: billable_metric.code,
            timestamp: event.timestamp + 1.second,
            transaction_id: "#{event.transaction_id}-other",
            properties: event_properties
          ))
        end
        let(:other_metered_item) { metered_item.with_event(event: other_event) }
        let(:other_fee_service) { described_class.new(metered_item: other_metered_item, billing_context:) }

        it "persists a separate fee for each transaction" do
          first = fee_service.call.fees.sole
          second = other_fee_service.call.fees.sole

          expect([first, second].map(&:pay_in_advance_event_transaction_id))
            .to eq([event.transaction_id, other_event.transaction_id])
          expect(first).to have_attributes(units: 1, amount_cents: 1000) # model(1) = 1 * 10 EUR * 100
          # count_agg over both events, standard model: model(2) - model(1) = 2000 - 1000
          expect(second).to have_attributes(units: 1, amount_cents: 1000, events_count: 1)
        end
      end
    end

    context "when two events of the same contract product are priced at once", transaction: false do
      let(:billable_metric) { create(:unique_count_billable_metric, organization:, field_name: "user_id") }
      let(:contract) { create(:contract, organization:, customer:) }
      let(:product) { create(:product, :metered, organization:, billable_metric:) }
      let(:rate_card) { create(:rate_card, :advance, organization:, product:, display_on_invoice: false) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
      let(:billing_segment) do
        create(:billing_segment, organization:, customer:, contract:, contract_rate_card:, currency: "EUR",
          rate_properties: {"amount" => "10"})
      end
      let(:billing_context) { Billing::Context.from(contract:) }
      let(:metered_items) do
        %w[user_1 user_2].map do |user_id|
          source = create(:event, organization_id: organization.id, external_subscription_id: contract.external_id,
            external_customer_id: customer.external_id, code: billable_metric.code,
            timestamp: billing_segment.started_at, properties: {"user_id" => user_id})
          Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:, event: Events::CommonFactory.new_instance(source:))
        end
      end
      let(:both_priced) { Concurrent::CountDownLatch.new(2) }

      before do
        metered_items
        allow(Charges::PayInAdvanceAggregationService).to receive(:call).and_call_original

        # Holds each fee between pricing and saving, so both read the state before either writes it.
        allow(Charges::ApplyPayInAdvanceChargeModelService).to receive(:call).and_wrap_original do |method, **kwargs|
          method.call(**kwargs).tap do
            both_priced.count_down
            both_priced.wait(1)
          end
        end
      end

      it "counts both events in the persisted state" do
        metered_items.map { |metered_item|
          Thread.new { described_class.call(metered_item:, billing_context:, billing_at: metered_item.event.timestamp) }
        }.each(&:join)

        # The latch reached zero, so both fees were priced before either was saved.
        expect(both_priced.count).to eq(0)
        # unique_count_agg: each event adds 1 user, priced at 1 * 10 EUR * 100 = 1000 cents
        expect(Fee.where(contract:).pluck(:units, :amount_cents)).to match_array([[1, 1000], [1, 1000]])
        expect(CachedAggregation.where(contract:, product:).maximum(:current_aggregation)).to eq(2)
      end
    end

    it "creates a fee" do
      result = fee_service.call

      expect(result).to be_success

      expect(result.fees.count).to eq(1)
      expect(result.fees.first).to have_attributes(
        subscription:,
        organization_id: organization.id,
        billing_entity_id: billing_entity.id,
        charge:,
        amount_cents: 10, # 1 event * 0.10 EUR = 0.10 EUR = 10 cents
        precise_amount_cents: 10.0, # 0.10 EUR * 100
        amount_currency: "EUR",
        fee_type: "charge",
        pay_in_advance: true,
        invoiceable: charge,
        units: 1, # count_agg: the one event of the period
        properties: Hash,
        events_count: 1,
        charge_filter: nil,
        pay_in_advance_event_id: event.id,
        pay_in_advance_event_transaction_id: event.transaction_id,
        payment_status: "pending",
        unit_amount_cents: 10, # 0.10 EUR / 1 unit = 0.10 EUR = 10 cents
        precise_unit_amount: 0.1, # 0.10 EUR / 1 unit

        taxes_rate: 0,
        taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0.0
      )
      expect(result.fees.first.applied_taxes.count).to eq(0)
    end

    it "returns a validation failure when the charge fee already exists" do
      fee_service.call

      retry_result = fee_service.call

      expect(retry_result.error.messages).to eq(pay_in_advance_event_transaction_id: ["pay_in_advance_fee_already_exists"])
      expect(Fee.where(pay_in_advance_event_transaction_id: event.transaction_id).sole).to have_attributes(
        amount_cents: 10, # 1 event * 0.10 EUR, from the first call only
        units: 1
      )
    end

    it "does not create pricing unit usage" do
      expect { fee_service.call }.not_to change(PricingUnitUsage, :count)
    end

    it "delivers a webhook" do
      result = fee_service.call

      expect(SendWebhookJob).to have_been_enqueued
        .with("fee.created", result.fees.sole)
    end

    context "when aggregation fails" do
      before do
        allow(Charges::PayInAdvanceAggregationService).to receive(:call).and_return(
          BillableMetrics::Aggregations::BaseService::Result.new.service_failure!(code: "failure", message: "Failure")
        )
      end

      it "returns a failure" do
        result = fee_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("failure")
        expect(result.error.error_message).to eq("Failure")
      end
    end

    context "when charge model fails" do
      before do
        allow(Charges::ApplyPayInAdvanceChargeModelService).to receive(:call).and_return(
          Charges::ApplyPayInAdvanceChargeModelService::Result.new.service_failure!(code: "failure", message: "Failure")
        )
      end

      it "returns a failure" do
        result = fee_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("failure")
        expect(result.error.error_message).to eq("Failure")
      end
    end

    context "when charge has a charge filter" do
      let(:event_properties) do
        {
          payment_method: "card",
          card_location: "domestic",
          scheme: "visa",
          card_type: "credit"
        }
      end

      let(:card_location) do
        create(:billable_metric_filter, billable_metric:, key: "card_location", values: %i[domestic])
      end
      let(:scheme) { create(:billable_metric_filter, billable_metric:, key: "scheme", values: %i[visa mastercard]) }

      # The filter price (1 EUR) differs from the charge price (0.10 EUR) to show which bucket priced the event.
      let(:filter) { create(:charge_filter, charge:, properties: {"amount" => "1"}) }
      let(:filter_values) do
        [
          create(
            :charge_filter_value,
            values: ["domestic"],
            billable_metric_filter: card_location,
            charge_filter: filter
          ),
          create(
            :charge_filter_value,
            values: %w[visa mastercard],
            billable_metric_filter: scheme,
            charge_filter: filter
          )
        ]
      end

      let(:charge_filter) { filter }

      before { filter_values }

      it "creates a fee" do
        result = fee_service.call

        expect(result).to be_success

        expect(result.fees.count).to eq(1)
        expect(result.fees.first).to have_attributes(
          subscription:,
          charge:,
          amount_cents: 100, # 1 event * 1 EUR (filter price) = 100 cents
          precise_amount_cents: 100.0,
          amount_currency: "EUR",
          fee_type: "charge",
          pay_in_advance: true,
          invoiceable: charge,
          units: 1,
          properties: Hash,
          events_count: 1,
          charge_filter:,
          pay_in_advance_event_id: event.id,
          pay_in_advance_event_transaction_id: event.transaction_id,
          unit_amount_cents: 100, # 1 EUR / 1 unit
          precise_unit_amount: 1.0,
          grouped_by: {},

          taxes_rate: 0,
          taxes_amount_cents: 0,
          taxes_precise_amount_cents: 0.0
        )
        expect(result.fees.first.applied_taxes.count).to eq(0)
      end

      context "with an earlier event outside the filter" do
        # Only the first unit of the filter bucket is priced, so the fee shows which events the bucket counts.
        let(:charge) do
          create(:graduated_charge, :pay_in_advance, billable_metric:, plan:, properties: graduated_properties)
        end
        let(:filter) { create(:charge_filter, charge:, properties: graduated_properties) }
        let(:graduated_properties) do
          {
            "graduated_ranges" => [
              {"from_value" => 0, "to_value" => 1, "per_unit_amount" => "1", "flat_amount" => "0"},
              {"from_value" => 2, "to_value" => nil, "per_unit_amount" => "0", "flat_amount" => "0"}
            ]
          }
        end

        before do
          # Same metric and subscription, scheme outside the filter's visa and mastercard values.
          create(
            :event,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            code: billable_metric.code,
            timestamp: event.timestamp - 1.second,
            properties: event_properties.merge(scheme: "amex")
          )
        end

        it "prices only the events of the filter bucket" do
          expect(fee_service.call.fees.sole).to have_attributes(
            charge_filter:,
            units: 1, # count_agg: the "visa" event, the "amex" one is left out by the filter
            events_count: 1,
            # graduated model(1) - model(0) = 1 * 1 EUR * 100 - 0; with the "amex" event counted it would be
            # model(2) - model(1) = 100 - 100 = 0
            amount_cents: 100,
            precise_amount_cents: 100.0
          )
        end
      end

      context "when charge filter has pricing_group_keys defined" do
        let(:charge_filter) { create(:charge_filter, charge:, properties: {:amount => "1", "pricing_group_keys" => ["group_key"]}) }
        let(:event_properties) do
          {
            payment_method: "card",
            card_location: "international",
            scheme: "visa",
            card_type: "credit",
            group_key: "group_value"
          }
        end

        before { create(:charge_filter_value, values: ["visa"], billable_metric_filter: scheme, charge_filter:) }

        it "creates a fee" do
          result = fee_service.call

          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 100, # 1 event * 1 EUR (filter price) = 100 cents
            precise_amount_cents: 100.0,
            amount_currency: "EUR",
            fee_type: "charge",
            pay_in_advance: true,
            invoiceable: charge,
            units: 1,
            properties: Hash,
            events_count: 1,
            charge_filter:,
            pay_in_advance_event_id: event.id,
            pay_in_advance_event_transaction_id: event.transaction_id,
            unit_amount_cents: 100, # 1 EUR / 1 unit
            precise_unit_amount: 1.0,
            grouped_by: {"group_key" => "group_value"},

            taxes_rate: 0,
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0.0
          )
          expect(result.fees.first.applied_taxes.count).to eq(0)
        end
      end

      context "when charge filter has a grouped_by defined" do
        let(:charge_filter) { create(:charge_filter, charge:, properties: {:amount => "1", "grouped_by" => ["group_key"]}) }
        let(:event_properties) do
          {
            payment_method: "card",
            card_location: "international",
            scheme: "visa",
            card_type: "credit",
            group_key: "group_value"
          }
        end

        before { create(:charge_filter_value, values: ["visa"], billable_metric_filter: scheme, charge_filter:) }

        it "creates a fee" do
          result = fee_service.call

          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 100, # 1 event * 1 EUR (filter price) = 100 cents
            precise_amount_cents: 100.0,
            amount_currency: "EUR",
            fee_type: "charge",
            pay_in_advance: true,
            invoiceable: charge,
            units: 1,
            properties: Hash,
            events_count: 1,
            charge_filter:,
            pay_in_advance_event_id: event.id,
            pay_in_advance_event_transaction_id: event.transaction_id,
            unit_amount_cents: 100, # 1 EUR / 1 unit
            precise_unit_amount: 1.0,
            grouped_by: {"group_key" => "group_value"},

            taxes_rate: 0,
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0.0
          )
          expect(result.fees.first.applied_taxes.count).to eq(0)
        end
      end

      context "when event does not match the charge filter" do
        let(:charge_filter) { nil }

        let(:event_properties) do
          {
            payment_method: "card",
            card_location: "international",
            scheme: "visa",
            card_type: "credit"
          }
        end

        it "creates a fee using the default filter" do
          expect(metered_item.pricing_buckets).to match([
            have_attributes(
              charge_filter: have_attributes(charge:, id: nil),
              properties: charge.properties
            )
          ])

          result = fee_service.call

          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 10, # 1 event * 0.10 EUR (charge price, default bucket) = 10 cents
            precise_amount_cents: 10.0,
            amount_currency: "EUR",
            fee_type: "charge",
            pay_in_advance: true,
            invoiceable: charge,
            units: 1,
            properties: Hash,
            events_count: 1,
            charge_filter_id: nil,
            pay_in_advance_event_id: event.id,
            pay_in_advance_event_transaction_id: event.transaction_id,
            unit_amount_cents: 10, # 0.10 EUR / 1 unit
            precise_unit_amount: 0.1,

            taxes_rate: 0,
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0.0
          )
          expect(result.fees.first.applied_taxes.count).to eq(0)
        end
      end
    end

    context "when charge has a grouped_by property" do
      # Only the first unit of each group is priced, so the fee shows which events the group counts.
      let(:charge) do
        create(
          :graduated_charge,
          billable_metric:,
          plan:,
          pay_in_advance: true,
          properties: {
            "grouped_by" => ["operator"],
            "graduated_ranges" => [
              {"from_value" => 0, "to_value" => 1, "per_unit_amount" => "2", "flat_amount" => "0"},
              {"from_value" => 2, "to_value" => nil, "per_unit_amount" => "0", "flat_amount" => "0"}
            ]
          }
        )
      end

      let(:event_properties) { {"operator" => "foo"} }

      before do
        # Same metric and subscription, other operator: outside the "foo" group, so not counted.
        create(
          :event,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: event.timestamp - 1.second,
          properties: {"operator" => "bar"}
        )
      end

      it "creates a fee" do
        result = fee_service.call

        expect(result).to be_success

        expect(result.fees.count).to eq(1)
        expect(result.fees.first).to have_attributes(
          subscription:,
          charge:,
          # graduated model(1) - model(0) = 1 * 2 EUR * 100 - 0; with the "bar" event counted it would be
          # model(2) - model(1) = 200 - 200 = 0
          amount_cents: 200,
          precise_amount_cents: 200.0,
          amount_currency: "EUR",
          fee_type: "charge",
          pay_in_advance: true,
          invoiceable: charge,
          units: 1,
          properties: Hash,
          events_count: 1,
          pay_in_advance_event_id: event.id,
          pay_in_advance_event_transaction_id: event.transaction_id,
          unit_amount_cents: 200, # 2 EUR / 1 unit
          precise_unit_amount: 2.0,
          grouped_by: {"operator" => "foo"},

          taxes_rate: 0,
          taxes_amount_cents: 0,
          taxes_precise_amount_cents: 0.0
        )
        expect(result.fees.first.applied_taxes.count).to eq(0)
      end
    end

    context "when event is not persisted" do
      let(:estimate) { true }
      let(:event) do
        Events::Common.new(
          id: nil,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          organization_id: organization.id,
          properties: event_properties,
          timestamp: Time.current,
          precise_total_amount_cents: nil,
          persisted: false
        )
      end

      it "does not persist the fee and defers taxes to the caller" do
        result = fee_service.call

        expect(result).to be_success

        expect(result.fees.count).to eq(1)
        expect(result.fees.first).not_to be_persisted
        expect(result.fees.first).to have_attributes(
          subscription:,
          charge:,
          # With the event: 1 unit * 0.10 EUR; without it: 0 units. 0.10 - 0 = 0.10 EUR = 10 cents
          amount_cents: 10,
          precise_amount_cents: 10.0,
          amount_currency: "EUR",
          fee_type: "charge",
          pay_in_advance: true,
          invoiceable: charge,
          units: 1,
          properties: Hash,
          events_count: 1,
          pay_in_advance_event_id: event.id,
          pay_in_advance_event_transaction_id: event.transaction_id,
          unit_amount_cents: 10, # 0.10 EUR / 1 unit
          precise_unit_amount: 0.1,

          taxes_rate: 0,
          taxes_amount_cents: 0,
          taxes_precise_amount_cents: 0.0
        )
        expect(result.fees.first.applied_taxes.size).to eq(0)
        expect(Fee.count).to eq(0)
      end

      context "with an earlier event in the period" do
        before do
          create(
            :event,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            code: billable_metric.code,
            timestamp: event.timestamp - 1.second
          )
        end

        it "prices only the delta added by the event" do
          expect(fee_service.call.fees.sole).to have_attributes(
            units: 1, # count_agg: the new event only, the earlier one is already billed
            events_count: 1,
            # With the event: 2 units * 0.10 EUR; without it: 1 unit * 0.10 EUR. 0.20 - 0.10 = 0.10 EUR = 10 cents
            amount_cents: 10,
            precise_amount_cents: 10.0
          )
        end
      end

      it "does not deliver a webhook" do
        fee_service.call

        expect(SendWebhookJob).not_to have_been_enqueued
          .with("fee.created", Fee)
      end

      context "when stimate is false" do
        let(:estimate) { false }

        it "raises an argument error" do
          expect { fee_service.call }
            .to raise_error(ArgumentError, "estimate must be true if event if not persisted")
        end
      end
    end

    context "with pricing unit on the charge" do
      let(:pricing_unit) { create(:pricing_unit, organization:) }

      before do
        create(
          :applied_pricing_unit,
          organization: subscription.organization,
          pricing_unit:,
          conversion_rate: 0.5,
          pricing_unitable: charge
        )
      end

      it "creates a fee with converted values" do
        result = fee_service.call

        expect(result).to be_success

        expect(result.fees.count).to eq(1)
        fee = result.fees.first
        expect(fee).to have_attributes(
          subscription:,
          organization_id: organization.id,
          billing_entity_id: billing_entity.id,
          charge:,
          amount_cents: 5, # 10 pricing unit cents * 0.5 = 5 cents
          amount_currency: "EUR",
          fee_type: "charge",
          pay_in_advance: true,
          invoiceable: charge,
          units: 1,
          events_count: 1,
          charge_filter: nil,
          pay_in_advance_event_id: event.id,
          pay_in_advance_event_transaction_id: event.transaction_id,
          payment_status: "pending",
          taxes_rate: 0,
          taxes_amount_cents: 0
        )
        expect(fee.precise_amount_cents).to eq(5) # 10 pricing unit cents * 0.5
        expect(fee.precise_unit_amount).to eq(BigDecimal("0.05")) # 0.10 pricing units per unit * 0.5
        expect(fee.taxes_precise_amount_cents).to eq(0)
        expect(result.fees.first.applied_taxes.count).to eq(0)
      end

      it "creates pricing unit usage" do
        result = fee_service.call

        expect(result).to be_success
        pricing_unit_usage = result.fees.first.pricing_unit_usage
        expect(pricing_unit_usage).to be_persisted
        expect(pricing_unit_usage).to have_attributes(
          pricing_unit_id: pricing_unit.id,
          short_name: pricing_unit.short_name,
          conversion_rate: 0.5,
          amount_cents: 10, # 1 event * 0.10 pricing units = 10 pricing unit cents
          precise_amount_cents: 10, # 0.10 pricing units * 100
          unit_amount_cents: 10 # 0.10 pricing units / 1 unit
        )
      end
    end

    context "when the metric is a sum aggregation" do
      let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "units") }
      let(:event_properties) { {"units" => "5"} }

      it "prices the event value" do
        result = fee_service.call

        expect(result.fees.sole).to have_attributes(
          amount_cents: 50, # 5 units * 0.10 EUR = 0.50 EUR = 50 cents
          precise_amount_cents: 50.0,
          units: 5,
          events_count: 1,
          unit_amount_cents: 10, # 0.50 EUR / 5 units = 0.10 EUR
          precise_unit_amount: 0.1
        )
      end

      it "creates a cached aggregation" do
        expect { fee_service.call }.to change(CachedAggregation, :count).by(1)

        # No cached row yet, so current = max = the event value (5)
        expect(CachedAggregation.sole).to have_attributes(
          organization_id: organization.id,
          event_transaction_id: event.transaction_id,
          charge_id: charge.id,
          external_subscription_id: event.external_subscription_id,
          charge_filter_id: nil,
          current_aggregation: 5,
          current_amount: nil,
          max_aggregation: 5,
          max_aggregation_with_proration: nil,
          grouped_by: {},
          presentation_breakdowns: []
        )
        expect(CachedAggregation.sole.timestamp.iso8601(3)).to eq(event.timestamp.iso8601(3))
      end

      context "with presentation_group_keys" do
        let(:charge) do
          create(:standard_charge, :pay_in_advance, billable_metric:, plan:,
            properties: {amount: "10", pricing_group_keys: ["cloud"], presentation_group_keys: [{"value" => "region"}]})
        end
        let(:event_properties) { {"cloud" => "aws", "region" => "us-east-1", "units" => "5"} }

        it "prices the event value in its pricing group" do
          expect(fee_service.call.fees.sole).to have_attributes(
            amount_cents: 5000, # 5 units * 10 EUR = 50 EUR = 5000 cents
            units: 5,
            grouped_by: {"cloud" => "aws"}
          )
        end

        it "stores presentation_breakdowns stripped of pricing group keys" do
          fee_service.call

          expect(CachedAggregation.sole.presentation_breakdowns).to eq([
            {"groups" => {"region" => "us-east-1"}, "value" => "5.0"}
          ])
        end

        it "builds presentation_breakdowns on the fee stripped of pricing group keys" do
          result = fee_service.call

          fee = result.fees.first
          expect(fee.presentation_breakdowns.map { |b| [b.presentation_by, b.units] }).to eq([[{"region" => "us-east-1"}, 5]])
          expect(fee.presentation_breakdowns).to all(have_attributes(organization_id: organization.id))
        end
      end
    end

    context "with sum aggregation and presentation_group_keys" do
      let(:event) { current_event }
      let(:current_event) { first_event }
      let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "units") }
      let(:charge) do
        create(
          :standard_charge,
          :pay_in_advance,
          billable_metric:,
          plan:,
          properties: {
            amount: "1",
            presentation_group_keys: [{"value" => "department"}, {"value" => "units"}]
          }
        )
      end
      let(:first_event) do
        Events::CommonFactory.new_instance(
          source: create(
            :event,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            code: billable_metric.code,
            timestamp: subscription.started_at + 1.hour,
            properties: {"units" => "3", "department" => "engineering"}
          )
        )
      end
      let(:second_event) do
        Events::CommonFactory.new_instance(
          source: create(
            :event,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            code: billable_metric.code,
            timestamp: subscription.started_at + 1.hour + 1.second,
            properties: {"units" => "10", "department" => "engineering"}
          )
        )
      end
      let(:third_event) do
        Events::CommonFactory.new_instance(
          source: create(
            :event,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            code: billable_metric.code,
            timestamp: subscription.started_at + 1.hour + 2.seconds,
            properties: {"units" => "7", "department" => "engineering"}
          )
        )
      end

      def process(previous_event)
        described_class.call!(
          metered_item: metered_item.with_event(event: previous_event),
          billing_context:,
          billing_at: previous_event.timestamp
        )
      end

      it "builds presentation breakdowns from the first event" do
        result = fee_service.call

        fee = result.fees.first
        expect(fee).to have_attributes(
          amount_cents: 300, # 3 units * 1 EUR = 300 cents
          units: 3
        )
        expect(fee.presentation_breakdowns.map { |b| [b.presentation_by, b.units] }).to eq([
          [{"department" => "engineering", "units" => "3"}, 3]
        ])

        expect(CachedAggregation.order(:timestamp).last).to have_attributes(
          current_aggregation: 3, # no cached row before: the event value
          max_aggregation: 3,
          presentation_breakdowns: [{"groups" => {"department" => "engineering", "units" => "3"}, "value" => "3.0"}]
        )
      end

      context "when the first event was already processed" do
        let(:current_event) { second_event }

        before { process(first_event) }

        it "builds presentation breakdowns from the second event" do
          result = fee_service.call

          fee = result.fees.first
          expect(fee).to have_attributes(
            amount_cents: 1000, # (3 + 10 - 3 already billed) units * 1 EUR = 1000 cents
            units: 10
          )
          expect(fee.presentation_breakdowns.map { |b| [b.presentation_by, b.units] }).to eq([
            [{"department" => "engineering", "units" => "10"}, 10]
          ])

          expect(CachedAggregation.order(:timestamp).last).to have_attributes(
            event_transaction_id: second_event.transaction_id,
            current_aggregation: 13, # 3 (first event) + 10
            max_aggregation: 13
          )
          expect(CachedAggregation.order(:timestamp).last.presentation_breakdowns).to match_array([
            {"groups" => {"department" => "engineering", "units" => "3"}, "value" => "3.0"},
            {"groups" => {"department" => "engineering", "units" => "10"}, "value" => "10.0"}
          ])
        end
      end

      context "when the first two events were already processed" do
        let(:current_event) { third_event }

        before do
          process(first_event)
          process(second_event)
        end

        it "builds presentation breakdowns from the third event" do
          result = fee_service.call

          fee = result.fees.first
          expect(fee).to have_attributes(
            amount_cents: 700, # (3 + 10 + 7 - 13 already billed) units * 1 EUR = 700 cents
            units: 7
          )
          expect(fee.presentation_breakdowns.map { |b| [b.presentation_by, b.units] }).to eq([
            [{"department" => "engineering", "units" => "7"}, 7]
          ])

          expect(CachedAggregation.order(:timestamp).last).to have_attributes(
            event_transaction_id: third_event.transaction_id,
            current_aggregation: 20, # 13 (first two events) + 7
            max_aggregation: 20
          )
          expect(CachedAggregation.order(:timestamp).last.presentation_breakdowns).to match_array([
            {"groups" => {"department" => "engineering", "units" => "3"}, "value" => "3.0"},
            {"groups" => {"department" => "engineering", "units" => "10"}, "value" => "10.0"},
            {"groups" => {"department" => "engineering", "units" => "7"}, "value" => "7.0"}
          ])
        end
      end
    end

    context "when charge is non-invoiceable" do
      let(:charge) do
        create(:standard_charge, :pay_in_advance, billable_metric:, plan:, invoiceable: false, properties: {"amount" => "0.10"})
      end

      context "when customer does not have a tax provider integration" do
        it "applies local taxes eagerly" do
          result = fee_service.call

          expect(result).to be_success

          fee = result.fees.sole.reload
          expect(fee).to have_attributes(
            amount_cents: 10, # 1 event * 0.10 EUR
            taxes_rate: 20.0,
            taxes_amount_cents: 2 # 10 cents * 20%
          )
          expect(fee.applied_taxes.map { |t| [t.tax_id, t.tax_rate, t.amount_cents] }).to eq([[tax.id, 20.0, 2]])
        end
      end

      context "when customer has tax provider integration" do
        let(:integration) { create(:anrok_integration, organization:) }
        let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
        let(:response) { instance_double(Net::HTTPOK) }
        let(:lago_client) { instance_double(LagoHttpClient::Client) }
        let(:endpoint) { "https://api.nango.dev/action/trigger" }
        # Built when the provider is called, after the fee is saved, so it answers for the real fee id.
        let(:body) do
          p = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json")
          json = File.read(p)

          response_data = JSON.parse(json)
          provider_fee = response_data["succeededInvoices"].first["fees"].first
          provider_fee["item_id"] = Fee.sole.id
          provider_fee["amount_cents"] = 10 # 1 event * 0.10 EUR
          provider_fee["tax_breakdown"].first["rate"] = "0.10"
          provider_fee["tax_breakdown"].first["tax_amount"] = 1 # 10 cents * 10%
          provider_fee["tax_amount_cents"] = 1

          response_data.to_json
        end

        let(:integration_collection_mapping) do
          create(
            :netsuite_collection_mapping,
            integration:,
            mapping_type: :fallback_item,
            settings: {external_id: "1", external_account_code: "11", external_name: ""}
          )
        end

        before do
          integration_collection_mapping
          integration_customer

          allow(LagoHttpClient::Client).to receive(:new)
            .with(endpoint, retries_on: [OpenSSL::SSL::SSLError])
            .and_return(lago_client)
          allow(lago_client).to receive(:post_with_response).and_return(response)
          allow(response).to receive(:body) { body }
        end

        it "applies provider taxes instead of local taxes" do
          result = fee_service.call

          expect(result).to be_success

          fee = result.fees.sole
          expect(fee).to have_attributes(
            amount_cents: 10, # 1 event * 0.10 EUR
            taxes_rate: 10.0, # provider rate 0.10 * 100; the 20% local tax is not applied
            taxes_amount_cents: 1 # provider answer: 10 cents * 10%
          )
          # Provider returns 2 tax breakdown entries (tax_exempt + exempt)
          expect(Fee::AppliedTax.where(fee:).map { |t| [t.tax_name, t.tax_rate, t.amount_cents] }).to match_array([
            ["GST/HST", 10.0, 1], # 10 cents * 10%
            ["Reverse charge", 0.0, 0]
          ])
        end
      end
    end
  end
end
