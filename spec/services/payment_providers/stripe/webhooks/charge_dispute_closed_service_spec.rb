# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Webhooks::ChargeDisputeClosedService, type: :service do
  subject(:service) { described_class.new(organization_id:, event:) }

  let(:organization_id) { organization.id }
  let(:organization) { create(:organization) }
  let(:membership) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:payment) { create(:payment, payable:, provider_payment_id: "pi_3OzgpDH4tiDZlIUa0Ezzggtg") }
  let(:event) { ::Stripe::Event.construct_from(JSON.parse(event_json)) }

  before { allow(::Payments::LoseDisputeService).to receive(:call).and_call_original }

  describe "#call" do
    before { payment }

    context "when payable is an invoice" do
      let(:payable) { create(:invoice, customer:, organization:, status:, payment_status: "succeeded") }

      context "when dispute is lost" do
        let(:event_json) do
          path = Rails.root.join("spec/fixtures/stripe/charge_dispute_lost_event.json")
          File.read(path)
        end

        context "when invoice is draft" do
          let(:status) { "draft" }

          it "does not updates invoice payment dispute lost" do
            expect do
              service.call
              payment.payable.reload
            end.not_to change(payment.payable.reload, :payment_dispute_lost_at).from(nil)
          end

          it "does not deliver webhook" do
            expect { service.call }.not_to have_enqueued_job(SendWebhookJob)
          end
        end

        context "when invoice is finalized" do
          let(:status) { "finalized" }

          it "updates invoice payment dispute lost" do
            expect do
              service.call
              payment.payable.reload
            end.to change(payment.payable, :payment_dispute_lost_at).from(nil)
          end

          it "delivers a webhook" do
            expect do
              service.call
              payment.payable.reload
            end.to have_enqueued_job(SendWebhookJob).with(
              "invoice.payment_dispute_lost",
              payment.payable,
              provider_error: "fraudulent"
            )
          end
        end
      end

      context "when dispute is won" do
        let(:event_json) do
          path = Rails.root.join("spec/fixtures/stripe/charge_dispute_won_event.json")
          File.read(path)
        end

        context "when invoice is draft" do
          let(:status) { "draft" }

          it "does not updates invoice payment dispute lost" do
            expect do
              service.call
              payment.payable.reload
            end.not_to change(payment.payable.reload, :payment_dispute_lost_at).from(nil)
          end

          it "does not deliver webhook" do
            expect { service.call }.not_to have_enqueued_job(SendWebhookJob)
          end
        end

        context "when invoice is finalized" do
          let(:status) { "finalized" }

          it "does not updates invoice payment dispute lost" do
            expect do
              service.call
              payment.payable.reload
            end.not_to change(payment.payable.reload, :payment_dispute_lost_at).from(nil)
          end

          it "does not deliver webhook" do
            expect { service.call }.not_to have_enqueued_job(SendWebhookJob)
          end
        end
      end
    end

    context "when payable is a payment request" do
      let(:payment) { create(:payment, payable:, provider_payment_id: "pi_3OzgpDH4tiDZlIUa0Ezzggtg") }
      let(:payable) { create(:payment_request, customer:, organization:, invoices: [invoice_1, invoice_2]) }
      let(:invoice_1) { create(:invoice, customer:, organization:, status: "finalized", payment_status: "succeeded") }
      let(:invoice_2) { create(:invoice, customer:, organization:, status: "finalized", payment_status: "succeeded") }

      context "when dispute is lost" do
        let(:event_json) do
          path = Rails.root.join("spec/fixtures/stripe/charge_dispute_lost_event.json")
          File.read(path)
        end

        it "flags all the invoices of the PaymentRequests" do
          service.call
          expect(::Payments::LoseDisputeService).to have_received(:call)
          expect(invoice_1.reload.payment_dispute_lost_at).to eq "2024-03-29 14:58:14 UTC"
          expect(invoice_2.reload.payment_dispute_lost_at).to eq "2024-03-29 14:58:14 UTC"

          expect(SendWebhookJob).to have_been_enqueued.once
            .with("invoice.payment_dispute_lost", invoice_1, provider_error: "fraudulent")
          expect(SendWebhookJob).to have_been_enqueued.once
            .with("invoice.payment_dispute_lost", invoice_2, provider_error: "fraudulent")

          expect(Invoices::ProviderTaxes::VoidJob).to have_been_enqueued.twice
        end
      end

      context "when dispute is won" do
        let(:event_json) do
          path = Rails.root.join("spec/fixtures/stripe/charge_dispute_won_event.json")
          File.read(path)
        end

        it "does not call LoseDisputeService" do
          service.call
          expect(::Payments::LoseDisputeService).not_to have_received(:call)
        end
      end
    end
  end
end
