# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::AddOnService do
  subject(:invoice_service) do
    described_class.new(applied_add_on:, datetime:)
  end

  let(:datetime) { Time.zone.now }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:billing_entity) { customer.billing_entity }
  let(:applied_add_on) { create(:applied_add_on, customer:) }

  let(:tax) { create(:tax, :applied_to_billing_entity, rate: 20, organization:) }

  before { tax }

  describe "create" do
    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it "creates an invoice" do
      result = invoice_service.create

      expect(result).to be_success

      expect(result.invoice.subscriptions.first).to be_nil
      expect(result.invoice).to have_attributes(
        organization: organization,
        billing_entity: customer.billing_entity,
        issuing_date: datetime.to_date,
        invoice_type: "add_on",
        payment_status: "pending",
        currency: "EUR",
        fees_amount_cents: 200,
        sub_total_excluding_taxes_amount_cents: 200,
        taxes_amount_cents: 40,
        taxes_rate: 20,
        sub_total_including_taxes_amount_cents: 240,
        total_amount_cents: 240
      )

      expect(result.invoice.applied_taxes.count).to eq(1)

      expect(result.invoice).to be_finalized
    end

    it "enqueues a SendWebhookJob" do
      expect do
        invoice_service.create
      end.to have_enqueued_job(SendWebhookJob)
    end

    it "enqueue an GenerateDocumentsJob with email false" do
      expect do
        invoice_service.create
      end.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: false))
    end

    context "with lago_premium" do
      around { |test| lago_premium!(&test) }

      it "enqueues an GenerateDocumentsJob with email true" do
        expect do
          invoice_service.create
        end.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: true))
      end

      context "when organization does not have right email settings" do
        before { applied_add_on.customer.billing_entity.update!(email_settings: []) }

        it "enqueue an GenerateDocumentsJob with email false" do
          expect do
            invoice_service.create
          end.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: false))
        end
      end
    end

    it "calls SegmentTrackJob" do
      invoice = invoice_service.create.invoice

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
      allow(Invoices::Payments::CreateService)
        .to receive(:call_async)

      invoice_service.create

      expect(Invoices::Payments::CreateService).to have_received(:call_async)
    end

    it_behaves_like "syncs invoice" do
      let(:service_call) { invoice_service.create }
    end

    it_behaves_like "applies invoice_custom_sections" do
      let(:service_call) { invoice_service.create }
    end

    context "with customer timezone" do
      before { applied_add_on.customer.update!(timezone: "America/Los_Angeles") }

      let(:datetime) { DateTime.parse("2022-11-25 01:00:00") }

      it "assigns the issuing date in the customer timezone" do
        result = invoice_service.create

        expect(result.invoice.issuing_date.to_s).to eq("2022-11-24")
      end
    end
  end
end
