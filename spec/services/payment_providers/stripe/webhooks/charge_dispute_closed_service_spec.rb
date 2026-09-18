# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Webhooks::ChargeDisputeClosedService do
  subject(:service) { described_class.new(organization_id:, event:) }

  let(:organization_id) { organization.id }
  let(:organization) { create(:organization) }
  let(:membership) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:intent_id) { "pi_3OzgpDH4tiDZlIUa0Ezzggtg" }
  let(:payment) { create(:payment, payable:, provider_payment_id: intent_id) }
  let(:event) { ::Stripe::Event.construct_from(JSON.parse(event_json)) }

  # NOTE: by default stripe reports the same state as the closing event
  let(:current_is_charge_refundable) { true }
  let(:current_disputes) do
    [{id: "dp_123456", object: "dispute", is_charge_refundable: current_is_charge_refundable}]
  end

  before do
    allow(::Payments::LoseDisputeService).to receive(:call).and_call_original
    allow(::Payments::CloseDisputeService).to receive(:call).and_call_original
    allow(::Stripe::Dispute).to receive(:list).and_return(
      ::Stripe::ListObject.construct_from(
        object: "list", url: "/v1/disputes", has_more: false, data: current_disputes
      )
    )
  end

  ["2020-08-27", "2025-04-30.basil"].each do |version|
    describe "#call" do
      before { payment }

      context "when payable is an invoice" do
        let(:payable) { create(:invoice, customer:, organization:, status:, payment_status: "succeeded") }

        context "when dispute is lost" do
          let(:event_json) do
            get_stripe_fixtures("webhooks/charge_dispute_closed.json", version:) do |h|
              if h.dig(:data, :object, :payment_intent)&.starts_with? "pi_"
                h[:data][:object][:payment_intent] = intent_id
              end
              h[:data][:object][:status] = "lost" if h.dig(:data, :object, :status)
            end
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
            get_stripe_fixtures("webhooks/charge_dispute_closed.json", version:) do |h|
              if h.dig(:data, :object, :payment_intent)&.starts_with? "pi_"
                h[:data][:object][:payment_intent] = intent_id
              end
              h[:data][:object][:status] = "won" if h.dig(:data, :object, :status)
            end
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
        let(:payment) { create(:payment, payable:, provider_payment_id: intent_id) }
        let(:payable) { create(:payment_request, customer:, organization:, invoices: [invoice_1, invoice_2]) }
        let(:invoice_1) { create(:invoice, customer:, organization:, status: "finalized", payment_status: "succeeded") }
        let(:invoice_2) { create(:invoice, customer:, organization:, status: "finalized", payment_status: "succeeded") }

        context "when dispute is lost" do
          let(:event_json) do
            get_stripe_fixtures("webhooks/charge_dispute_closed.json", version:) do |h|
              if h.dig(:data, :object, :payment_intent)&.starts_with? "pi_"
                h[:data][:object][:payment_intent] = intent_id
              end
              h[:data][:object][:status] = "lost" if h.dig(:data, :object, :status)
            end
          end

          it "flags all the invoices of the PaymentRequests" do
            service.call
            expect(::Payments::LoseDisputeService).to have_received(:call)
            expect(invoice_1.reload.payment_dispute_lost_at).to eq Time.zone.at(event.created)
            expect(invoice_2.reload.payment_dispute_lost_at).to eq Time.zone.at(event.created)

            expect(SendWebhookJob).to have_been_enqueued.once
              .with("invoice.payment_dispute_lost", invoice_1, provider_error: "fraudulent")
            expect(SendWebhookJob).to have_been_enqueued.once
              .with("invoice.payment_dispute_lost", invoice_2, provider_error: "fraudulent")

            expect(Invoices::ProviderTaxes::VoidJob).to have_been_enqueued.twice
          end
        end

        context "when dispute is won" do
          let(:event_json) do
            get_stripe_fixtures("webhooks/charge_dispute_closed.json", version:) do |h|
              if h.dig(:data, :object, :payment_intent)&.starts_with? "pi_"
                h[:data][:object][:payment_intent] = intent_id
              end
              h[:data][:object][:status] = "won" if h.dig(:data, :object, :status)
            end
          end

          it "does not call LoseDisputeService" do
            service.call
            expect(::Payments::LoseDisputeService).not_to have_received(:call)
          end
        end
      end

      context "when a stale close arrives while another dispute still blocks refunds" do
        let(:payable) do
          create(:invoice, :refund_blocked, customer:, organization:, status: "finalized", payment_status: "succeeded")
        end
        # NOTE: the closing dispute reports the charge as refundable, but a newer dispute on the
        #       same payment intent does not.
        let(:current_disputes) do
          [
            {id: "dp_closed", object: "dispute", is_charge_refundable: true},
            {id: "dp_newer", object: "dispute", is_charge_refundable: false}
          ]
        end
        let(:event_json) do
          get_stripe_fixtures("webhooks/charge_dispute_closed.json", version:) do |h|
            h[:data][:object][:payment_intent] = intent_id
            h[:data][:object][:status] = "won"
            h[:data][:object][:is_charge_refundable] = true
          end
        end

        it "does not unblock refunds" do
          expect { service.call && payable.reload }.not_to change(payable, :payment_refund_blocked_at)
        end

        it "does not call CloseDisputeService" do
          service.call

          expect(::Payments::CloseDisputeService).not_to have_received(:call)
        end
      end

      context "when the dispute has no payment intent" do
        let(:intent_id) { nil }
        let(:payable) { create(:invoice, customer:, organization:, status: "finalized") }
        let(:event_json) do
          get_stripe_fixtures("webhooks/charge_dispute_closed.json", version:) do |h|
            h[:data][:object][:payment_intent] = nil
            h[:data][:object][:status] = "lost"
          end
        end

        it "does not mark the payment's invoice as dispute lost" do
          expect { service.call && payable.reload }.not_to change(payable, :payment_dispute_lost_at).from(nil)
        end

        it "does not call LoseDisputeService" do
          service.call

          expect(::Payments::LoseDisputeService).not_to have_received(:call)
        end
      end

      context "when the payment belongs to another organization" do
        let(:other_organization) { create(:organization) }
        let(:other_customer) { create(:customer, organization: other_organization) }
        let(:payable) do
          create(:invoice, customer: other_customer, organization: other_organization, status: "finalized")
        end
        let(:event_json) do
          get_stripe_fixtures("webhooks/charge_dispute_closed.json", version:) do |h|
            h[:data][:object][:payment_intent] = intent_id
            h[:data][:object][:status] = "lost"
          end
        end

        it "does not touch the other organization's invoice" do
          expect { service.call && payable.reload }.not_to change(payable, :payment_dispute_lost_at).from(nil)
        end

        it "does not call LoseDisputeService" do
          service.call

          expect(::Payments::LoseDisputeService).not_to have_received(:call)
        end
      end

      context "with an invoice whose refunds are blocked" do
        let(:payable) do
          create(:invoice, :refund_blocked, customer:, organization:, status: "finalized", payment_status: "succeeded")
        end
        let(:event_json) do
          get_stripe_fixtures("webhooks/charge_dispute_closed.json", version:) do |h|
            h[:data][:object][:payment_intent] = intent_id
            h[:data][:object][:status] = status
            h[:data][:object][:is_charge_refundable] = is_charge_refundable
          end
        end

        context "when the dispute is won" do
          let(:status) { "won" }
          let(:is_charge_refundable) { true }

          it "clears the dispute flag" do
            expect { service.call && payable.reload }.to change(payable, :payment_refund_blocked_at).to(nil)
          end
        end

        context "when the dispute is closed as a warning" do
          let(:status) { "warning_closed" }
          let(:is_charge_refundable) { true }

          it "clears the dispute flag" do
            expect { service.call && payable.reload }.to change(payable, :payment_refund_blocked_at).to(nil)
          end

          it "does not call LoseDisputeService" do
            service.call
            expect(::Payments::LoseDisputeService).not_to have_received(:call)
          end
        end

        context "when the dispute is lost" do
          let(:status) { "lost" }
          let(:is_charge_refundable) { false }
          let(:current_is_charge_refundable) { false }

          # NOTE: the charge stays unrefundable, so the flag must survive and keep blocking refunds
          #       even if marking the invoice as dispute lost fails.
          it "leaves the dispute flag in place" do
            expect { service.call && payable.reload }.not_to change(payable, :payment_refund_blocked_at)
          end

          it "marks the invoice as dispute lost" do
            expect { service.call && payable.reload }.to change(payable, :payment_dispute_lost_at).from(nil)
          end
        end
      end
    end
  end
end
