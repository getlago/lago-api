# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CreateOneOffService do
  let(:args) { {customer:, timestamp: timestamp.to_i, fees:, currency:} }
  let(:timestamp) { Time.zone.now.beginning_of_month }
  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:customer) { create(:customer, organization:, billing_entity:) }
  let(:tax) { create(:tax, :applied_to_billing_entity, billing_entity:, organization:, rate: 20) }
  let(:currency) { "EUR" }
  let(:add_on_first) { create(:add_on, organization:) }
  let(:add_on_second) { create(:add_on, amount_cents: 400, organization:) }
  let(:fees) do
    [
      {
        add_on_code: add_on_first.code,
        unit_amount_cents: 1200,
        units: 2,
        description: "desc-123"
      },
      {
        add_on_code: add_on_second.code
      }
    ]
  end

  describe "call" do
    before do
      tax

      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::TransitionToFinalStatusService).to receive(:call).and_call_original
      CurrentContext.source = "api"
    end

    it "creates an invoice" do
      result = described_class.call(**args)

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.issuing_date.to_date).to eq(timestamp)
        expect(result.invoice.invoice_type).to eq("one_off")
        expect(result.invoice.payment_status).to eq("pending")
        expect(result.invoice.fees.where(fee_type: :add_on).count).to eq(2)
        expect(result.invoice.fees.pluck(:description)).to contain_exactly("desc-123", add_on_second.description)

        expect(result.invoice.currency).to eq("EUR")
        expect(result.invoice.fees_amount_cents).to eq(2800)

        expect(result.invoice.taxes_amount_cents).to eq(560)
        expect(result.invoice.taxes_rate).to eq(20)
        expect(result.invoice.applied_taxes.count).to eq(1)

        expect(result.invoice.total_amount_cents).to eq(3360)
        expect(result.invoice.voided_invoice_id).to be_nil

        expect(result.invoice).to be_finalized
        expect(Invoices::TransitionToFinalStatusService).to have_received(:call).with(invoice: result.invoice)
      end
    end

    context "when voided invoice id is passed" do
      let(:voided_invoice_id) { SecureRandom.uuid }
      let(:args) { {customer:, timestamp: timestamp.to_i, fees:, currency:, voided_invoice_id:} }

      it "creates an invoice" do
        result = described_class.call(**args)

        expect(result).to be_success
        expect(result.invoice.voided_invoice_id).to eq(voided_invoice_id)
      end
    end

    it_behaves_like "syncs invoice" do
      let(:service_call) { described_class.call(**args) }
    end

    it_behaves_like "applies invoice_custom_sections" do
      let(:service_call) { described_class.call(**args) }
    end

    it "calls SegmentTrackJob" do
      invoice = described_class.call(**args).invoice

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

      described_class.call(**args)

      expect(Invoices::Payments::CreateService).to have_received(:call_async)
    end

    context "when skip_payment is true" do
      it "does not create a payment" do
        allow(Invoices::Payments::CreateService).to receive(:call_async)

        described_class.call(**args.merge(skip_psp: true))

        expect(Invoices::Payments::CreateService).not_to have_received(:call_async)
      end
    end

    it "enqueues a SendWebhookJob" do
      expect do
        described_class.call(**args)
      end.to have_enqueued_job(SendWebhookJob)
    end

    it "enqueues GenerateDocumentsJob with email false" do
      expect do
        described_class.call(**args)
      end.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: false))
    end

    context "when there is tax provider integration" do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
      let(:response) { instance_double(Net::HTTPOK) }
      let(:lago_client) { instance_double(LagoHttpClient::Client) }
      let(:endpoint) { "https://api.nango.dev/v1/anrok/finalized_invoices" }
      let(:body) do
        p = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response_multiple_fees.json")
        json = File.read(p)

        # setting item_id based on the test example
        response = JSON.parse(json)
        response["succeededInvoices"].first["fees"].first["item_id"] = "fee_id_1"
        response["succeededInvoices"].first["fees"].first["tax_breakdown"].first["tax_amount"] = 240
        response["succeededInvoices"].first["fees"].last["item_id"] = "fee_id_2"
        response["succeededInvoices"].first["fees"].last["tax_breakdown"].first["tax_amount"] = 60

        response.to_json
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
        allow_any_instance_of(Fee).to receive(:id).and_wrap_original do |m, *args| # rubocop:disable RSpec/AnyInstance
          fee = m.receiver
          if fee.add_on_id == add_on_first.id
            "fee_id_1"
          elsif fee.add_on_id == add_on_second.id
            "fee_id_2"
          else
            m.call(*args)
          end
        end
      end

      it "produces an activity log" do
        invoice = described_class.call(**args).invoice

        expect(Utils::ActivityLog).to have_produced("invoice.one_off_created").after_commit.with(invoice)
      end

      it "creates an invoice" do
        result = described_class.call(**args)

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.issuing_date.to_date).to eq(timestamp)
          expect(result.invoice.invoice_type).to eq("one_off")
          expect(result.invoice.payment_status).to eq("pending")
          expect(result.invoice.fees.where(fee_type: :add_on).count).to eq(2)
          expect(result.invoice.fees.pluck(:description)).to contain_exactly("desc-123", add_on_second.description)

          expect(result.invoice.currency).to eq("EUR")
          expect(result.invoice.fees_amount_cents).to eq(2800) # 2400 + 400

          expect(result.invoice.taxes_amount_cents).to eq(300) # (2400 * 0.1) + (400 * 0.15)
          expect(result.invoice.taxes_rate).to eq(10.71429)
          expect(result.invoice.applied_taxes.count).to eq(2)

          expect(result.invoice.total_amount_cents).to eq(3100)

          expect(result.invoice).to be_finalized

          expect(result.invoice.reload.error_details.count).to eq(0)
        end
      end

      it "saves applies taxes on fees and on invoice" do
        result = described_class.call(**args)
        invoice = result.invoice.reload

        expect(invoice.applied_taxes.count).to eq(2)
        expect(invoice.fees.map(&:applied_taxes).flatten.count).to eq(2)
        expect(invoice.fees.map(&:taxes_rate).sort).to eq([10.0, 15.0])
      end

      context "when there is error received from the provider" do
        let(:body) do
          p = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")
          File.read(p)
        end

        it "returns tax error" do
          result = described_class.call(**args)

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.status).to eq("failed")
            expect(result.invoice.error_details.count).to eq(1)
            expect(result.invoice.error_details.first.details["tax_error"]).to eq("taxDateTooFarInFuture")
            expect(Utils::ActivityLog).to have_produced("invoice.failed").with(result.invoice)
          end
        end
      end
    end

    context "when invoice amount in cents is zero" do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 0,
            units: 2,
            description: "desc-123"
          }
        ]
      end

      it "creates a payment_succeeded invoice" do
        result = described_class.call(**args)

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.issuing_date.to_date).to eq(timestamp)
          expect(result.invoice.invoice_type).to eq("one_off")
          expect(result.invoice.payment_status).to eq("succeeded")
          expect(result.invoice.fees.where(fee_type: :add_on).count).to eq(1)
          expect(result.invoice.fees.pluck(:description)).to contain_exactly("desc-123")

          expect(result.invoice.currency).to eq("EUR")
          expect(result.invoice.fees_amount_cents).to eq(0)
          expect(result.invoice.taxes_amount_cents).to eq(0)
          expect(result.invoice.taxes_rate).to eq(20)
          expect(result.invoice.total_amount_cents).to eq(0)

          expect(result.invoice).to be_finalized
        end
      end
    end

    context "with lago_premium" do
      around { |test| lago_premium!(&test) }

      it "enqueues GenerateDocumentsJob with email true" do
        expect do
          described_class.call(**args)
        end.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: true))
      end

      context "when organization does not have right email settings" do
        before { customer.billing_entity.update!(email_settings: []) }

        it "enqueues GenerateDocumentsJob with email false" do
          expect do
            described_class.call(**args)
          end.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: false))
        end
      end
    end

    context "with customer timezone" do
      before { customer.update!(timezone: "America/Los_Angeles") }

      let(:timestamp) { DateTime.parse("2022-11-25 01:00:00") }

      it "assigns the issuing date in the customer timezone" do
        result = described_class.call(**args)

        expect(result.invoice.issuing_date.to_s).to eq("2022-11-24")
      end
    end

    context "when currency does not match" do
      let(:currency) { "NOK" }

      it "fails" do
        result = described_class.call(**args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:currency)
          expect(result.error.messages[:currency]).to include("currencies_does_not_match")
        end
      end
    end

    context "when currency does not present" do
      let(:currency) { nil }

      before { customer.update!(currency: nil) }

      it "fails" do
        result = described_class.call(**args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:currency)
          expect(result.error.messages[:currency]).to include("value_is_mandatory")
        end
      end
    end

    context "when customer is not found" do
      let(:customer) { nil }

      it "returns a not found error" do
        result = described_class.call(**args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq("customer_not_found")
        end
      end
    end

    context "when fees are blank" do
      let(:fees) { [] }

      it "returns a not found error" do
        result = described_class.call(**args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq("fees_not_found")
        end
      end
    end

    context "when add_on_code is invalid" do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: "desc-123"
          },
          {
            add_on_code: "invalid"
          }
        ]
      end

      it "returns a not found error" do
        result = described_class.call(**args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq("add_on_not_found")
        end
      end
    end
  end

  describe "#tax_error?" do
    subject(:method_call) { described_class.new(**args).__send__(:tax_error?, result) }

    let(:result) { BaseService::Result.new }

    context "when the fee result is successful" do
      it "returns false" do
        expect(subject).to be false
      end
    end

    context "when the fee result is not successful" do
      context "when the fee result error code is tax_error" do
        before do
          result.service_failure!(code: "tax_error", message: "Tax error")
        end

        it "returns true" do
          expect(subject).to be true
        end
      end

      context "when the fee result error does not respond to code" do
        before do
          result.validation_failure!(errors: [{message: "error"}])
        end

        it "returns false" do
          expect(subject).to be false
        end
      end

      context "when the fee result error code is not tax_error" do
        before do
          result.service_failure!(code: "code1", message: "Code1 error")
        end

        it "returns false" do
          expect(subject).to be false
        end
      end
    end
  end
end
