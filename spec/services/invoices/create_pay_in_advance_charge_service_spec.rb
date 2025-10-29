# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CreatePayInAdvanceChargeService do
  subject(:invoice_service) do
    described_class.new(charge:, event:, timestamp: timestamp.to_i)
  end

  let(:timestamp) { Time.zone.now.beginning_of_month }
  let(:organization) { create(:organization) }
  let(:billing_entity) { customer.billing_entity }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:charge) { create(:standard_charge, :pay_in_advance, billable_metric:, plan:) }
  let(:charge_filter) { nil }

  let(:email_settings) { ["invoice.finalized", "credit_note.created"] }

  let(:event) do
    Events::CommonFactory.new_instance(
      source: create(
        :event,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        organization_id: organization.id
      )
    )
  end

  before do
    create(:tax, :applied_to_billing_entity, organization:)
    billing_entity.update!(email_settings:)
  end

  describe "call" do
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
        result.amount_details = {}
      end
    end

    before do
      allow(Charges::PayInAdvanceAggregationService).to receive(:call)
        .with(charge:, boundaries: BillingPeriodBoundaries, properties: Hash, event:, charge_filter:)
        .and_return(aggregation_result)

      allow(Charges::ApplyPayInAdvanceChargeModelService).to receive(:call)
        .with(charge:, aggregation_result:, properties: Hash)
        .and_return(charge_result)

      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::TransitionToFinalStatusService).to receive(:call).and_call_original
    end

    it "creates an invoice" do
      result = invoice_service.call

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.issuing_date.to_date).to eq(timestamp)
        expect(result.invoice.payment_due_date.to_date).to eq(timestamp)
        expect(result.invoice.organization_id).to eq(organization.id)
        expect(result.invoice.customer_id).to eq(customer.id)
        expect(result.invoice.invoice_type).to eq("subscription")
        expect(result.invoice.payment_status).to eq("pending")

        expect(result.invoice.fees.where(fee_type: :charge).count).to eq(1)
        expect(result.invoice.fees.first).to have_attributes(
          subscription:,
          charge:,
          amount_cents: 10,
          precise_amount_cents: 10.0,
          amount_currency: "EUR",
          taxes_rate: 20.0,
          taxes_amount_cents: 2,
          taxes_precise_amount_cents: 2.0,
          fee_type: "charge",
          pay_in_advance: true,
          invoiceable: charge,
          units: 9,
          properties: Hash,
          events_count: 1,
          charge_filter: nil,
          pay_in_advance_event_id: event.id,
          payment_status: "pending",
          unit_amount_cents: 1,
          precise_unit_amount: 0.01111111111
        )

        expect(result.invoice.currency).to eq(customer.currency)
        expect(result.invoice.fees_amount_cents).to eq(10)

        expect(result.invoice.taxes_amount_cents).to eq(2)
        expect(result.invoice.taxes_rate).to eq(20)
        expect(result.invoice.applied_taxes.count).to eq(1)

        expect(result.invoice.total_amount_cents).to eq(12)

        expect(Invoices::TransitionToFinalStatusService).to have_received(:call).with(invoice: result.invoice)
        expect(result.invoice).to be_finalized
      end
    end

    it "creates InvoiceSubscription object" do
      expect { invoice_service.call.invoice }.to change(InvoiceSubscription, :count).by(1)
    end

    it "calls SegmentTrackJob" do
      invoice = invoice_service.call.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: "invoice_created",
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type
        }
      )
    end

    it "creates a payment" do
      allow(Invoices::Payments::CreateService).to receive(:call_async)

      invoice_service.call

      expect(Invoices::Payments::CreateService).to have_received(:call_async)
    end

    it "enqueues a SendWebhookJob for the invoice" do
      expect do
        invoice_service.call
      end.to have_enqueued_job(SendWebhookJob).with("invoice.created", Invoice)
    end

    it "enqueues a SendWebhookJob for the fees" do
      expect do
        invoice_service.call
      end.to have_enqueued_job(SendWebhookJob).with("fee.created", Fee)
    end

    it "produces an activity log" do
      invoice = described_class.call(charge:, event:, timestamp: timestamp.to_i).invoice

      expect(Utils::ActivityLog).to have_produced("invoice.created").with(invoice)
    end

    it "enqueues GenerateDocumentsJob with email false" do
      expect do
        invoice_service.call
      end.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: false))
    end

    context "with lago_premium" do
      around { |test| lago_premium!(&test) }

      it "enqueues GenerateDocumentsJob with email true" do
        expect do
          invoice_service.call
        end.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: true))
      end

      context "when organization does not have right email settings" do
        let(:email_settings) { [] }

        it "enqueues GenerateDocumentsJob with email false" do
          expect do
            invoice_service.call
          end.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: false))
        end
      end
    end

    context "with customer timezone" do
      let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
      let(:timestamp) { DateTime.parse("2022-11-25 01:00:00") }

      it "assigns the issuing date in the customer timezone" do
        result = invoice_service.call

        expect(result.invoice.issuing_date.to_s).to eq("2022-11-24")
        expect(result.invoice.payment_due_date.to_s).to eq("2022-11-24")
      end
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

      it "creates an invoice and fees" do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees_amount_cents).to eq(10)
          expect(result.invoice.taxes_amount_cents).to eq(1)
          expect(result.invoice.taxes_rate).to eq(10)
          expect(result.invoice.total_amount_cents).to eq(11)
          expect(result.invoice).to be_finalized

          expect(result.invoice.reload.error_details.count).to eq(0)
        end
      end

      context "when there is error received from the provider" do
        let(:body) do
          p = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")
          File.read(p)
        end

        it "returns tax error" do
          result = described_class.call(charge:, event:, timestamp: timestamp.to_i)

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:tax_error]).to eq(["taxDateTooFarInFuture"])

            invoice = customer.invoices.order(created_at: :desc).first

            expect(invoice.status).to eq("failed")
            expect(invoice.error_details.count).to eq(1)
            expect(invoice.error_details.first.details["tax_error"]).to eq("taxDateTooFarInFuture")
            expect(Utils::ActivityLog).to have_produced("invoice.failed").with(invoice)
          end
        end
      end
    end

    context "with grace period" do
      let(:customer) { create(:customer, organization:, invoice_grace_period: 3) }
      let(:timestamp) { DateTime.parse("2022-11-25 08:00:00") }

      it "assigns the correct issuing date" do
        result = invoice_service.call

        expect(result.invoice.issuing_date.to_s).to eq("2022-11-25")
      end
    end

    it_behaves_like "applies invoice_custom_sections" do
      let(:service_call) { invoice_service.call }
    end

    context "when an error occurs" do
      context "with a stale object error" do
        before { create(:wallet, customer:, balance_cents: 100) }

        it "propagates the error" do
          allow_any_instance_of(Credits::AppliedPrepaidCreditService) # rubocop:disable RSpec/AnyInstance
            .to receive(:call).and_raise(ActiveRecord::StaleObjectError)

          expect { invoice_service.call }.to raise_error(ActiveRecord::StaleObjectError)
        end
      end

      context "with a sequence error" do
        it "propagates the error" do
          allow_any_instance_of(Invoice) # rubocop:disable RSpec/AnyInstance
            .to receive(:save!).and_raise(Sequenced::SequenceError)

          expect { invoice_service.call }.to raise_error(Sequenced::SequenceError)
        end
      end
    end
  end
end
