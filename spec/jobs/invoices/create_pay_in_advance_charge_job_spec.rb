# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CreatePayInAdvanceChargeJob do
  describe "#perform" do
    let(:organization) { create(:organization) }
    let(:subscription) { create(:subscription, organization:) }
    let(:charge) do
      create(:standard_charge, :pay_in_advance, organization:, plan: subscription.plan, invoiceable: true)
    end
    let(:event) { create(:event, organization:, external_subscription_id: subscription.external_id) }
    let(:timestamp) { Time.current.to_i }

    let(:invoice) { nil }
    let(:result) { Invoices::CreatePayInAdvanceChargeService::Result.new }

    before do
      allow(Invoices::CreatePayInAdvanceChargeService).to receive(:call)
        .with(
          metered_item: instance_of(Fees::ChargeService::MeteredItem),
          billing_context: instance_of(Billing::Context),
          timestamp:
        )
        .and_return(result)
    end

    it "calls the create pay in advance charge service" do
      described_class.perform_now(charge:, event:, timestamp:)

      expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:call)
    end

    context "when the event has no billing context" do
      let(:event) do
        create(:event, organization:, external_subscription_id: "unknown-#{SecureRandom.uuid}")
      end

      before { allow(Rails.logger).to receive(:error) }

      it "skips the service call and logs the event" do
        described_class.perform_now(charge:, event:, timestamp:)

        expect(Invoices::CreatePayInAdvanceChargeService).not_to have_received(:call)
        expect(Rails.logger).to have_received(:error)
          .with(/no billing context for event.*charge_id=#{charge.id}/)
      end
    end

    context "when result is a failure" do
      let(:result) do
        Invoices::CreatePayInAdvanceChargeService::Result.new.single_validation_failure!(error_code: "error")
      end

      it "raises an error" do
        expect do
          described_class.perform_now(charge:, event:, timestamp:)
        end.to raise_error(BaseService::FailedResult)

        expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:call)
      end

      context "with a previously created invoice" do
        let(:invoice) { create(:invoice, :generating) }

        it "raises an error" do
          expect do
            described_class.perform_now(charge:, event:, timestamp:, invoice:)
          end.to raise_error(BaseService::FailedResult)

          expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:call)
        end
      end

      context "when no invoice is attached to the result" do
        let(:result_invoice) { create(:invoice, :draft) }

        before { result.invoice = nil }

        it "raises an error" do
          expect do
            described_class.perform_now(charge:, event:, timestamp:)
          end.to raise_error(BaseService::FailedResult)

          expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:call)
        end
      end
    end

    describe "retry_on" do
      [
        [Sequenced::SequenceError.new("Sequenced::SequenceError"), 15],
        [BaseLockService::FailedToAcquireLock.new("customer-1-prepaid_credit"), 25],
        [ActiveRecord::StaleObjectError.new("Attempted to update a stale object: Wallet."), 25],
        [BaseService::ThrottlingError.new(provider_name: "Stripe"), 25]
      ].each do |error, attempts|
        error_class = error.class

        context "when a #{error_class} error is raised" do
          before do
            allow(Invoices::CreatePayInAdvanceChargeService).to receive(:call).and_raise(error)
          end

          it "raises a #{error_class.name} error and retries" do
            assert_performed_jobs(attempts, only: [described_class]) do
              expect do
                described_class.perform_later(charge:, event:, timestamp:)
              end.to raise_error(error_class)
            end
          end
        end
      end
    end
  end
end
