# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Webhooks::ChargeDisputeCreatedService do
  subject(:service) { described_class.new(organization_id:, event:) }

  let(:organization_id) { organization.id }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:intent_id) { "pi_3OzgpDH4tiDZlIUa0Ezzggtg" }
  let(:payment) { create(:payment, payable:, provider_payment_id: intent_id) }
  let(:event) { ::Stripe::Event.construct_from(JSON.parse(event_json)) }
  let(:is_charge_refundable) { false }

  before do
    allow(::Payments::OpenDisputeService).to receive(:call).and_call_original
    allow(::Payments::CloseDisputeService).to receive(:call).and_call_original
  end

  ["2020-08-27", "2025-04-30.basil"].each do |version|
    describe "#call" do
      let(:event_json) do
        get_stripe_fixtures("webhooks/charge_dispute_created.json", version:) do |h|
          h[:data][:object][:payment_intent] = intent_id
          h[:data][:object][:is_charge_refundable] = is_charge_refundable
        end
      end

      context "when payable is an invoice" do
        let(:payable) { create(:invoice, customer:, organization:, status:, payment_status: "succeeded") }
        let(:status) { "finalized" }

        before { payment }

        it "blocks refunds on the invoice" do
          expect { service.call && payable.reload }
            .to change(payable, :payment_refund_blocked_at).from(nil).to(Time.zone.at(event.created))
        end

        it "does not deliver a webhook" do
          expect { service.call }.not_to have_enqueued_job(SendWebhookJob)
        end

        it "does not flag the invoice as dispute lost" do
          expect { service.call && payable.reload }.not_to change(payable, :payment_dispute_lost_at).from(nil)
        end

        context "when the invoice is draft" do
          let(:status) { "draft" }

          # NOTE: unlike payment_dispute_lost_at, this column carries no validation so that
          #       recording an inbound dispute can never fail.
          it "still blocks refunds on the invoice" do
            expect { service.call && payable.reload }.to change(payable, :payment_refund_blocked_at).from(nil)
          end
        end

        context "when the charge is still refundable" do
          let(:is_charge_refundable) { true }
          let(:payable) do
            create(:invoice, :refund_blocked, customer:, organization:, status:, payment_status: "succeeded")
          end

          it "clears the dispute flag" do
            expect { service.call && payable.reload }.to change(payable, :payment_refund_blocked_at).to(nil)
          end

          it "does not open a dispute" do
            service.call
            expect(::Payments::OpenDisputeService).not_to have_received(:call)
          end
        end

        context "when the dispute was already lost" do
          let(:payable) do
            create(:invoice, :dispute_lost, customer:, organization:, status:, payment_status: "succeeded")
          end

          it "does not block refunds on the invoice" do
            expect { service.call && payable.reload }.not_to change(payable, :payment_refund_blocked_at).from(nil)
          end
        end

        context "when the event is replayed" do
          it "keeps the first timestamp" do
            service.call
            first_value = payable.reload.payment_refund_blocked_at

            expect { service.call && payable.reload }.not_to change(payable, :payment_refund_blocked_at).from(first_value)
          end
        end
      end

      context "when payable is a payment request" do
        let(:payable) { create(:payment_request, customer:, organization:, invoices: [invoice_1, invoice_2]) }
        let(:invoice_1) { create(:invoice, customer:, organization:, status: "finalized", payment_status: "succeeded") }
        let(:invoice_2) { create(:invoice, customer:, organization:, status: "finalized", payment_status: "succeeded") }

        before { payment }

        it "flags all the invoices of the payment request" do
          service.call

          expect(::Payments::OpenDisputeService).to have_received(:call)
          expect(invoice_1.reload.payment_refund_blocked_at).to eq Time.zone.at(event.created)
          expect(invoice_2.reload.payment_refund_blocked_at).to eq Time.zone.at(event.created)
        end
      end

      context "when the payment does not exist" do
        let(:payable) { create(:invoice, customer:, organization:, status: "finalized") }

        it "returns a success result without opening a dispute" do
          expect(service.call).to be_success
          expect(::Payments::OpenDisputeService).not_to have_received(:call)
        end
      end

      context "when the payment belongs to another organization" do
        let(:other_organization) { create(:organization) }
        let(:other_customer) { create(:customer, organization: other_organization) }
        let(:payable) do
          create(:invoice, customer: other_customer, organization: other_organization, status: "finalized")
        end

        before { payment }

        it "does not flag the invoice" do
          expect { service.call && payable.reload }.not_to change(payable, :payment_refund_blocked_at).from(nil)
        end
      end
    end
  end
end
