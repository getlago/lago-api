# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::CreatePayInAdvanceService do
  subject(:fee_service) { described_class.new(charge:, event:, billing_at: event.timestamp, estimate:) }

  let(:billing_entity) { create(:billing_entity) }
  let(:organization) { billing_entity.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }

  let(:charge_filter) { nil }

  let(:charge) { create(:standard_charge, :pay_in_advance, billable_metric:, plan:) }
  let(:estimate) { false }

  let(:event) do
    Events::CommonFactory.new_instance(
      source: create(
        :event,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        organization_id: organization.id,
        properties: event_properties
      )
    )
  end

  let(:event_properties) { {} }

  before { tax }

  describe "#call" do
    let(:aggregation_result) do
      BaseService::Result.new.tap do |result|
        result.aggregation = 9
        result.count = 4
        result.options = {}
      end
    end

    let(:charge_result) do
      BaseService::Result.new.tap do |result|
        result.amount = 10
        result.precise_amount = 10.0
        result.unit_amount = 0.01111111111
        result.count = 1
        result.units = 9
      end
    end

    before do
      allow(Charges::PayInAdvanceAggregationService).to receive(:call)
        .with(charge:, boundaries: BillingPeriodBoundaries, properties: Hash, event:, charge_filter:)
        .and_return(aggregation_result)

      allow(Charges::ApplyPayInAdvanceChargeModelService).to receive(:call)
        .with(charge:, aggregation_result:, properties: Hash)
        .and_return(charge_result)
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
        amount_cents: 10,
        precise_amount_cents: 10.0,
        amount_currency: "EUR",
        fee_type: "charge",
        pay_in_advance: true,
        invoiceable: charge,
        units: 9,
        properties: Hash,
        events_count: 1,
        charge_filter: nil,
        pay_in_advance_event_id: event.id,
        pay_in_advance_event_transaction_id: event.transaction_id,
        payment_status: "pending",
        unit_amount_cents: 1,
        precise_unit_amount: 0.01111111111,

        taxes_rate: 20.0,
        taxes_amount_cents: 2,
        taxes_precise_amount_cents: 2.0
      )
      expect(result.fees.first.applied_taxes.count).to eq(1)
    end

    it "does not create pricing unit usage" do
      expect { fee_service.call }.not_to change(PricingUnitUsage, :count)
    end

    it "delivers a webhook" do
      fee_service.call

      expect(SendWebhookJob).to have_been_enqueued
        .with("fee.created", Fee)
    end

    context "when there is tax provider integration" do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
      let(:response) { instance_double(Net::HTTPOK) }
      let(:lago_client) { instance_double(LagoHttpClient::Client) }
      let(:endpoint) { "https://api.nango.dev/v1/anrok/finalized_invoices" }
      let(:body) do
        p = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json")
        File.read(p)
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
        allow(response).to receive(:body).and_return(body)
        allow_any_instance_of(Fee).to receive(:id).and_return("lago_fee_id") # rubocop:disable RSpec/AnyInstance
      end

      it "creates fees" do
        result = fee_service.call

        expect(result).to be_success

        expect(result.fees.count).to eq(1)
        expect(result.fees.first).to have_attributes(
          subscription:,
          charge:,
          organization_id: organization.id,
          billing_entity_id: billing_entity.id,
          amount_cents: 10,
          precise_amount_cents: 10.0,
          amount_currency: "EUR",
          fee_type: "charge",
          pay_in_advance: true,
          invoiceable: charge,
          units: 9,
          properties: Hash,
          events_count: 1,
          charge_filter: nil,
          pay_in_advance_event_id: event.id,
          pay_in_advance_event_transaction_id: event.transaction_id,
          payment_status: "pending",
          unit_amount_cents: 1,
          precise_unit_amount: 0.01111111111,
          taxes_rate: 10.0,
          taxes_amount_cents: 1,
          taxes_precise_amount_cents: 1.0
        )
        expect(result.fees.first.applied_taxes.count).to eq(2)
      end

      context "when there is error received from the provider" do
        let(:body) do
          p = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")
          File.read(p)
        end

        it "returns tax error" do
          result = fee_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:tax_error]).to eq(["taxDateTooFarInFuture"])
            expect(charge.reload.fees.count).to eq(1)
          end
        end

        context "when invoiceable is false" do
          let(:charge) { create(:standard_charge, :pay_in_advance, billable_metric:, plan:, invoiceable: false) }

          it "returns tax error and fee is not being stored" do
            result = fee_service.call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)
              expect(result.error.messages[:tax_error]).to eq(["taxDateTooFarInFuture"])
              expect(charge.reload.fees.count).to eq(0)
            end
          end
        end
      end
    end

    context "when aggregation fails" do
      let(:aggregation_result) do
        BaseService::Result.new.service_failure!(code: "failure", message: "Failure")
      end

      it "returns a failure" do
        result = fee_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq("failure")
          expect(result.error.error_message).to eq("Failure")
        end
      end
    end

    context "when charge model fails" do
      let(:charge_result) do
        BaseService::Result.new.service_failure!(code: "failure", message: "Failure")
      end

      it "returns a failure" do
        result = fee_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq("failure")
          expect(result.error.error_message).to eq("Failure")
        end
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

      let(:filter) { create(:charge_filter, charge:) }
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
          amount_cents: 10,
          precise_amount_cents: 10.0,
          amount_currency: "EUR",
          fee_type: "charge",
          pay_in_advance: true,
          invoiceable: charge,
          units: 9,
          properties: Hash,
          events_count: 1,
          charge_filter:,
          pay_in_advance_event_id: event.id,
          pay_in_advance_event_transaction_id: event.transaction_id,
          unit_amount_cents: 1,
          precise_unit_amount: 0.01111111111,

          taxes_rate: 20.0,
          taxes_amount_cents: 2,
          taxes_precise_amount_cents: 2.0
        )
        expect(result.fees.first.applied_taxes.count).to eq(1)
      end

      context "when chargefilter has a grouped_by defined" do
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

        it "creates a fee" do
          result = fee_service.call

          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 10,
            precise_amount_cents: 10.0,
            amount_currency: "EUR",
            fee_type: "charge",
            pay_in_advance: true,
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            charge_filter:,
            pay_in_advance_event_id: event.id,
            pay_in_advance_event_transaction_id: event.transaction_id,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01111111111,
            grouped_by: {"group_key" => "group_value"},

            taxes_rate: 20.0,
            taxes_amount_cents: 2,
            taxes_precise_amount_cents: 2.0
          )
          expect(result.fees.first.applied_taxes.count).to eq(1)
        end
      end

      context "when event does not match the charge filter" do
        let(:charge_filter) { ChargeFilter }

        let(:event_properties) do
          {
            payment_method: "card",
            card_location: "international",
            scheme: "visa",
            card_type: "credit"
          }
        end

        it "creates a fee" do
          result = fee_service.call

          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 10,
            precise_amount_cents: 10.0,
            amount_currency: "EUR",
            fee_type: "charge",
            pay_in_advance: true,
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            charge_filter_id: nil,
            pay_in_advance_event_id: event.id,
            pay_in_advance_event_transaction_id: event.transaction_id,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01111111111,

            taxes_rate: 20.0,
            taxes_amount_cents: 2,
            taxes_precise_amount_cents: 2.0
          )
          expect(result.fees.first.applied_taxes.count).to eq(1)
        end
      end
    end

    context "when charge has a grouped_by property" do
      let(:charge) do
        create(
          :standard_charge,
          billable_metric:,
          pay_in_advance: true,
          properties: {"grouped_by" => ["operator"], "amount" => "100"}
        )
      end

      let(:event) do
        Events::CommonFactory.new_instance(
          source: create(
            :event,
            organization:,
            external_subscription_id: subscription.external_id,
            properties: {"operator" => "foo"}
          )
        )
      end

      it "creates a fee" do
        result = fee_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 10,
            precise_amount_cents: 10.0,
            amount_currency: "EUR",
            fee_type: "charge",
            pay_in_advance: true,
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            pay_in_advance_event_id: event.id,
            pay_in_advance_event_transaction_id: event.transaction_id,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01111111111,
            grouped_by: {"operator" => "foo"},

            taxes_rate: 20.0,
            taxes_amount_cents: 2,
            taxes_precise_amount_cents: 2.0
          )
          expect(result.fees.first.applied_taxes.count).to eq(1)
        end
      end
    end

    context "when in estimate mode" do
      let(:estimate) { true }

      it "does not persist the fee" do
        result = fee_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).not_to be_persisted
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 10,
            precise_amount_cents: 10.0,
            amount_currency: "EUR",
            fee_type: "charge",
            pay_in_advance: true,
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            pay_in_advance_event_id: event.id,
            pay_in_advance_event_transaction_id: event.transaction_id,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01111111111,

            taxes_rate: 20.0,
            taxes_amount_cents: 2,
            taxes_precise_amount_cents: 2.0
          )
          expect(result.fees.first.applied_taxes.size).to eq(1)
        end
      end

      context "when customer has a tax customer" do
        let(:integration) { create(:anrok_integration, organization:) }
        let(:integration_customer) { create(:anrok_customer, integration:, customer:, organization:) }
        let(:anrok_response_body) do
          p = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json")
          anrok_response_body = File.read(p)
          # Replace placeholder lago_fee_id with billable_metric.id
          anrok_response_body.gsub("lago_fee_id", billable_metric.id)
        end
        let(:anrok_request_body) do
          [
            {
              "issuing_date" => Time.zone.today.to_s,
              "currency" => "EUR",
              "contact" => {
                "external_id" => integration_customer.external_customer_id,
                "name" => customer.name,
                "address_line_1" => customer.address_line1,
                "city" => customer.city,
                "zip" => customer.zipcode,
                "country" => customer.country,
                "taxable" => false,
                "tax_number" => nil
              },
              "fees" => [
                {
                  "item_key" => a_kind_of(Integer),
                  "item_id" => billable_metric.id,
                  "item_code" => nil,
                  "amount_cents" => 10
                }
              ],
              "id" => a_kind_of(String)
            }
          ]
        end

        def mock_anrok_request
          stub_request(:post, "https://api.nango.dev/v1/anrok/finalized_invoices")
            .with(body: anrok_request_body)
            .to_return(status: 200, body: anrok_response_body)
        end

        before do
          integration_customer

          mock_anrok_request
        end

        it "calculates taxes" do
          result = fee_service.call

          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            organization_id: organization.id,
            billing_entity_id: billing_entity.id,
            amount_cents: 10,
            precise_amount_cents: 10.0,
            amount_currency: "EUR",
            fee_type: "charge",
            pay_in_advance: true,
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            charge_filter: nil,
            pay_in_advance_event_id: event.id,
            pay_in_advance_event_transaction_id: event.transaction_id,
            payment_status: "pending",
            unit_amount_cents: 1,
            precise_unit_amount: 0.01111111111,
            taxes_rate: 10.0,
            taxes_amount_cents: 1,
            taxes_precise_amount_cents: 1.0
          )
        end
      end

      it "does not deliver a webhook" do
        fee_service.call

        expect(SendWebhookJob).not_to have_been_enqueued
          .with("fee.created", Fee)
      end
    end

    context "with pricing unit on the charge" do
      before do
        create(
          :applied_pricing_unit,
          organization: subscription.organization,
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
          amount_cents: 5,
          amount_currency: "EUR",
          fee_type: "charge",
          pay_in_advance: true,
          invoiceable: charge,
          units: 9,
          events_count: 1,
          charge_filter: nil,
          pay_in_advance_event_id: event.id,
          pay_in_advance_event_transaction_id: event.transaction_id,
          payment_status: "pending",
          unit_amount_cents: 0,
          taxes_rate: 20.0,
          taxes_amount_cents: 1
        )
        expect(fee.precise_amount_cents.to_f).to eq(5.0)
        expect(fee.precise_unit_amount.to_f).to eq(0.005)
        expect(fee.taxes_precise_amount_cents.to_f).to eq(1.0)
        expect(result.fees.first.applied_taxes.count).to eq(1)
      end

      it "creates pricing unit usage" do
        result = fee_service.call

        expect(result).to be_success
        pricing_unit_usage = result.fees.first.pricing_unit_usage
        expect(pricing_unit_usage).to be_persisted
        expect(pricing_unit_usage.amount_cents).to eq(10)
        expect(pricing_unit_usage.precise_amount_cents.to_f).to eq(10.0)
        expect(pricing_unit_usage.unit_amount_cents).to eq(1)
      end
    end

    context "when in current and max aggregation result" do
      let(:aggregation_result) do
        BaseService::Result.new.tap do |result|
          result.amount = 10
          result.count = 1
          result.units = 9
          result.current_aggregation = 9
          result.max_aggregation = 9
          result.max_aggregation_with_proration = nil
        end
      end

      it "creates a cached aggregation" do
        aggregate_failures do
          expect { fee_service.call }.to change(CachedAggregation, :count).by(1)

          cached_aggregation = CachedAggregation.last
          expect(cached_aggregation.organization_id).to eq(organization.id)
          expect(cached_aggregation.event_transaction_id).to eq(event.transaction_id)
          expect(cached_aggregation.timestamp.iso8601(3)).to eq(event.timestamp.iso8601(3))
          expect(cached_aggregation.charge_id).to eq(charge.id)
          expect(cached_aggregation.external_subscription_id).to eq(event.external_subscription_id)
          expect(cached_aggregation.charge_filter_id).to be_nil
          expect(cached_aggregation.current_aggregation).to eq(9)
          expect(cached_aggregation.current_amount).to be_nil
          expect(cached_aggregation.max_aggregation).to eq(9)
          expect(cached_aggregation.max_aggregation_with_proration).to be_nil
          expect(cached_aggregation.grouped_by).to eq({})
        end
      end
    end
  end
end
