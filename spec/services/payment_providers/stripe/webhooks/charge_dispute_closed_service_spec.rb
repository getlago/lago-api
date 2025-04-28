# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Webhooks::ChargeDisputeClosedService, type: :service do
  subject(:service) { described_class.new(organization_id:, event:) }

  let(:organization_id) { organization.id }
  let(:organization) { create(:organization) }
  let(:membership) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:payment) { create(:payment, payable:, provider_payment_id: "pi_3OzgpDH4tiDZlIUa0Ezzggtg") }
  let(:lose_dispute_service) { Invoices::LoseDisputeService.new(payable:) }
  let(:event) { ::Stripe::Event.construct_from(JSON.parse(event_json)) }

  describe "#call" do
    before { payment }

    context "when payable is not an invoice" do
      let(:payment) { create(:payment, payable:, provider_payment_id: "pi_3OzgpDH4tiDZlIUa0Ezzggtg") }
      let(:payable) { create(:payment_request, customer:, organization:) }

      before { allow(Invoices::LoseDisputeService).to receive(:call) }

      context "when dispute is lost" do
        let(:event_json) do
          path = Rails.root.join("spec/fixtures/stripe/charge_dispute_lost_event.json")
          File.read(path)
        end

        it "does not call LoseDisputeService" do
          service.call
          expect(Invoices::LoseDisputeService).not_to have_received(:call)
        end
      end

      context "when dispute is won" do
        let(:event_json) do
          path = Rails.root.join("spec/fixtures/stripe/charge_dispute_won_event.json")
          File.read(path)
        end

        it "does not call LoseDisputeService" do
          service.call
          expect(Invoices::LoseDisputeService).not_to have_received(:call)
        end
      end
    end

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
  end
end
