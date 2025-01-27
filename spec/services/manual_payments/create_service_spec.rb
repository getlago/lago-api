# frozen_string_literal: true

require "rails_helper"

RSpec.describe ManualPayments::CreateService, type: :service do
  subject(:service) { described_class.new(organization:, params:) }

  let(:invoice) { create(:invoice, customer:, organization:, total_amount_cents: 10000, status: :finalized) }
  let(:invoice_id) { invoice.id }
  let(:organization) { create(:organization, premium_integrations:) }
  let(:customer) { create(:customer, organization:) }
  let(:params) { {invoice_id:, amount_cents:, reference: "ref1", paid_at:} }
  let(:paid_at) { 1.year.ago.iso8601 }
  let(:amount_cents) { 10000 }

  describe "#call" do
    context "when organization is not premium" do
      let(:premium_integrations) { %w[] }

      it "returns forbidden failure" do
        result = service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
        end
      end
    end

    context "when organization is premium" do
      around { |test| lago_premium!(&test) }

      context "with the premium_integration disabled" do
        let(:premium_integrations) { %w[] }

        it "returns forbidden failure" do
          result = service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ForbiddenFailure)
          end
        end
      end

      context "with the premium_integration enabled" do
        let(:premium_integrations) { %w[manual_payments] }

        context "when invoice does not exist" do
          let(:invoice_id) { SecureRandom.uuid }

          it "returns not found failure" do
            result = service.call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::NotFoundFailure)
            end
          end
        end

        context "when invoice's payment request is succeeded" do
          let(:payment_request) { create(:payment_request, payment_status: "succeeded") }

          before do
            create(:payment_request_applied_invoice, invoice:, payment_request:)
          end

          it "returns validation failure" do
            result = service.call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)
            end
          end
        end

        context "when payment amount cents is greater than invoice's remaining amount cents" do
          let(:amount_cents) { 10001 }

          it "returns validation failure" do
            result = service.call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)
            end
          end
        end

        context "when paid_at format is invalid" do
          let(:paid_at) { "invalid_date" }

          it "returns unprocessable entity failure" do
            result = service.call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)
              expect(result.error.messages[:paid_at]).to eq(["invalid_date"])
            end
          end
        end

        context "when payment amount cents is smaller than invoice remaining amount cents" do
          let(:amount_cents) { 2000 }

          it "creates a payment" do
            result = service.call

            expect(result).to be_success
            expect(result.payment.payment_type).to eq("manual")
            expect(result.payment.created_at).to eq(paid_at)
          end

          it "updates invoice's total paid amount cents" do
            result = service.call
            expect(result.payment.payable.total_paid_amount_cents).to eq(amount_cents)
          end

          context "when there is an integration customer" do
            let(:integration) do
              create(
                :netsuite_integration,
                organization:,
                settings: {
                  account_id: "acc_12345",
                  client_id: "cli_12345",
                  script_endpoint_url: Faker::Internet.url,
                  sync_payments: true
                }
              )
            end

            before { create(:netsuite_customer, integration:, customer:) }

            it "enqueues an aggregator payment job" do
              expect { service.call }.to have_enqueued_job(Integrations::Aggregator::Payments::CreateJob)
            end
          end
        end

        context "when payment amount cents is equal to invoice remaining amount cents" do
          let(:amount_cents) { 10000 }

          it "creates a payment" do
            result = service.call

            expect(result).to be_success
            expect(result.payment.payment_type).to eq("manual")
          end

          it "updates invoice's total paid amount cents" do
            result = service.call

            expect(result.payment.payable.total_paid_amount_cents).to eq(amount_cents)
          end

          it "updates invoice's payment status to suceeded" do
            result = service.call

            aggregate_failures do
              expect(result.payment.payable.payment_status).to eq("succeeded")
              expect(result.payment.payable_payment_status).to eq("succeeded")
            end
          end
        end
      end
    end
  end
end
