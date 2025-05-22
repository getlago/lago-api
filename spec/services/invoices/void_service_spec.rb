# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::VoidService, type: :service do
  describe "#call" do
    context "when invoice is nil" do
      let(:invoice) { nil }

      it "returns a failure" do
        result = described_class.call(invoice:)

        aggregate_failures do
          expect(result).not_to be_success

          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("invoice")
        end
      end
    end

    context "when invoice is draft" do
      let(:invoice) { create(:invoice, :draft) }

      it "returns a failure" do
        result = described_class.call(invoice:)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("not_voidable")
        end
      end
    end

    context "when the invoice is voided" do
      let(:invoice) { create(:invoice, status: :voided) }

      it "returns a failure" do
        result = described_class.call(invoice:)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("not_voidable")
        end
      end
    end

    context "when the invoice is finalized" do
      let(:invoice) { create(:invoice, :subscription, subscriptions:, status: :finalized, payment_status:, payment_overdue: true) }
      let(:subscriptions) { create_list(:subscription, 1) }

      context "when the payment status is succeeded" do
        let(:payment_status) { :succeeded }

        it "returns a failure" do
          result = described_class.call(invoice:)

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
            expect(result.error.code).to eq("not_voidable")
          end
        end
      end

      context "when the payment status is not succeeded" do
        let(:payment_status) { [:pending, :failed].sample }

        before do
          allow(Utils::ActivityLog).to receive(:produce)
        end

        it "voids the invoice" do
          result = described_class.call(invoice:)

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice).to be_voided
            expect(result.invoice.voided_at).to be_present
            # expect(result.invoice.balance_amount_cents).to eq(0)
          end
        end

        it "enqueues a sync void invoice job" do
          expect do
            described_class.call(invoice:)
          end.to have_enqueued_job(Invoices::ProviderTaxes::VoidJob).with(invoice:)
        end

        it "marks the invoice's payment overdue as false" do
          expect { described_class.call(invoice:) }.to change(invoice, :payment_overdue).from(true).to(false)
        end

        it "flags lifetime usage for refresh" do
          create(:usage_threshold, plan: subscriptions.first.plan)

          described_class.call(invoice:)

          expect(invoice.subscriptions.first.lifetime_usage.recalculate_invoiced_usage).to be(true)
        end

        it "produces an activity log" do
          invoice = described_class.call(invoice:).invoice

          expect(Utils::ActivityLog).to have_received(:produce).with(invoice, "invoice.voided")
        end
      end
    end
  end
end
