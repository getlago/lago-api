# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReceipts::CreateService, type: :service do
  subject(:service) { described_class.new(payment:) }

  let(:invoice) { create(:invoice, customer:, organization:, total_amount_cents: 10000, status: :finalized) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:payment) { create(:payment, payable: invoice) }

  describe "#call" do
    context "when issuing receipts is not enabled" do
      it "returns forbidden failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end
    end

    context "when issuing receipts is enabled" do
      around { |test| lago_premium!(&test) }
      before { organization.update!(premium_integrations: %w[issue_receipts]) }

      context "when customer is a partner account" do
        let(:customer) { create(:customer, organization:, account_type: :partner) }

        it "returns result" do
          result = service.call

          expect(result).to be_success
          expect(result.payment_receipt).to be_nil
        end
      end

      context "when customer is not a partner account" do
        context "when payment does not exist" do
          let(:payment) { nil }

          it "returns not found failure" do
            result = service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
          end
        end

        context "when payment exists" do
          context "when payment receipt already exists" do
            before { create(:payment_receipt, payment:, organization:) }

            it "returns result" do
              result = service.call

              expect(result).to be_success
              expect(result.payment_receipt).to be_nil
            end
          end

          context "when payment receipt does not exist" do
            before { payment.update!(payable_payment_status:) }

            context "when payment is not succeeded" do
              let(:payable_payment_status) { Payment::PAYABLE_PAYMENT_STATUS.reject { _1 == "succeeded" }.sample }

              it "returns result" do
                result = service.call

                expect(result).to be_success
                expect(result.payment_receipt).to be_nil
              end
            end

            context "when payment is succeeded" do
              let(:payable_payment_status) { "succeeded" }
              let(:payment_receipt) { build(:payment_receipt) }

              before do
                allow(PaymentReceipt).to receive(:new).and_return(payment_receipt)
              end

              it "creates the payment receipt" do
                expect { service.call }.to change(PaymentReceipt, :count).by(1)
              end

              it "enqueues the webhook job" do
                expect do
                  service.call
                end.to have_enqueued_job(SendWebhookJob).with("payment_receipt.created", payment_receipt)
              end

              it "enqueues the generate pdf job" do
                expect do
                  organization.email_settings << "payment_receipt.created"
                  organization.save!
                  service.call
                end.to have_enqueued_job(PaymentReceipts::GeneratePdfAndNotifyJob).with(payment_receipt:, email: true)
              end
            end
          end
        end
      end
    end
  end
end
