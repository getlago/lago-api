# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::ResendService do
  subject(:service) { described_class.new(resource:, to:, cc:, bcc:) }

  let(:to) { nil }
  let(:customer) { create(:customer, organization:, email: "customer@example.com") }
  let(:billing_entity) { customer.billing_entity }
  let(:cc) { nil }
  let(:bcc) { nil }

  let_it_be(:organization, refind: true) { create_default(:organization) }

  before do
    billing_entity.update!(email: "billing@example.com")
    billing_entity.email_settings = ["invoice.finalized", "credit_note.created", "payment_receipt.created"]
    billing_entity.save!
    allow(License).to receive(:premium?).and_return(true)
  end

  describe "#call" do
    context "when resource is nil" do
      let(:resource) { nil }

      it "returns a not found failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("resource")
      end
    end

    context "with an invoice" do
      let(:resource) { create(:invoice, organization:, customer:, status:, fees_amount_cents: 1000) }

      context "when invoice is finalized" do
        let(:status) { :finalized }

        it "sends the email successfully" do
          expect do
            result = service.call
            expect(result).to be_success
          end.to have_enqueued_mail(InvoiceMailer, :created)
        end

        context "with custom recipients" do
          let(:to) { ["custom@example.com", "another@example.com"] }
          let(:cc) { ["cc@example.com"] }
          let(:bcc) { ["bcc@example.com"] }

          it "sends the email with custom recipients" do
            expect do
              result = service.call
              expect(result).to be_success
            end.to have_enqueued_mail(InvoiceMailer, :created)
          end
        end
      end

      context "when invoice is draft" do
        let(:status) { :draft }

        it "returns a not allowed failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("invoice_not_finalized")
        end
      end

      context "when premium license is not available" do
        let(:status) { :finalized }

        before { allow(License).to receive(:premium?).and_return(false) }

        it "returns a forbidden failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("premium_license_required")
        end
      end

      context "when email settings are disabled" do
        let(:status) { :finalized }

        before do
          billing_entity.email_settings = []
          billing_entity.save!
        end

        it "sends the email successfully" do
          expect do
            result = service.call
            expect(result).to be_success
          end.to have_enqueued_mail(InvoiceMailer, :created)
        end
      end

      context "when no sender email address is configured" do
        let(:status) { :finalized }
        let(:previous_from_email) { ENV["LAGO_FROM_EMAIL"] }

        before do
          previous_from_email
          ENV["LAGO_FROM_EMAIL"] = nil
        end

        after { ENV["LAGO_FROM_EMAIL"] = previous_from_email }

        it "returns a validation failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:from]).to include("must have a sender email address configured")
          expect(result.error.codes).to eq(base: ["sender_email_not_configured"])
        end

        context "when the organization sends from its own email address" do
          before { organization.update!(premium_integrations: ["from_email"]) }

          it "sends the email successfully" do
            expect do
              result = service.call
              expect(result).to be_success
            end.to have_enqueued_mail(InvoiceMailer, :created)
          end
        end
      end

      context "when the invoice has no fees" do
        let(:status) { :finalized }
        let(:resource) { create(:invoice, organization:, customer:, status:, fees_amount_cents: 0) }

        it "returns a validation failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:invoice]).to include("must have a non-zero fees amount")
          expect(result.error.codes).to eq(base: ["zero_amount_invoice"])
        end
      end

      context "when billing entity has no email" do
        let(:status) { :finalized }

        before { billing_entity.update!(email: nil) }

        it "returns a validation failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:billing_entity]).to include("must have email configured")
          expect(result.error.codes).to eq(base: ["billing_entity_email_not_configured"])
        end
      end

      context "when custom recipient has invalid email format" do
        let(:status) { :finalized }
        let(:to) { ["invalid-email"] }

        it "returns a validation failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:to]).to include("invalid email format: invalid-email")
          expect(result.error.codes).to eq(to: ["invalid_email_format"])
        end
      end

      context "when cc and bcc recipients have an invalid email format" do
        let(:status) { :finalized }
        let(:cc) { ["cc@example.com", "invalid-cc"] }
        let(:bcc) { ["invalid-bcc", "other-invalid-bcc"] }

        it "returns a validation failure on each field" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq(cc: ["invalid email format: invalid-cc"], bcc: ["invalid email format: invalid-bcc, other-invalid-bcc"])
          expect(result.error.codes).to eq(cc: ["invalid_email_format"], bcc: ["invalid_email_format"])
        end
      end

      context "when the billing entity has no email and the invoice has no fees" do
        let(:status) { :finalized }
        let(:resource) { create(:invoice, organization:, customer:, status:, fees_amount_cents: 0) }
        let(:to) { ["invalid-email"] }

        before { billing_entity.update!(email: nil) }

        it "returns every refusal, on base for the fields that are not recipients" do
          result = service.call

          expect(result.error.messages).to eq(
            billing_entity: ["must have email configured"],
            invoice: ["must have a non-zero fees amount"],
            to: ["invalid email format: invalid-email"]
          )
          expect(result.error.codes).to eq(base: %w[billing_entity_email_not_configured zero_amount_invoice], to: ["invalid_email_format"])
        end
      end

      context "when custom recipient has a unicode local-part" do
        let(:status) { :finalized }
        let(:to) { ["joão.silva@example.com"] }

        it "sends the email successfully" do
          expect do
            result = service.call
            expect(result).to be_success
          end.to have_enqueued_mail(InvoiceMailer, :created)
        end
      end

      context "when customer has no email and no custom recipient" do
        let(:status) { :finalized }

        before { customer.update!(email: nil) }

        it "returns a validation failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:to]).to include("must have at least one recipient")
          expect(result.error.codes).to eq(to: ["value_is_mandatory"])
        end
      end
    end

    context "with a credit note" do
      let(:invoice) { create(:invoice, organization:, customer:, status: :finalized) }
      let(:resource) { create(:credit_note, invoice:, customer:, status:) }

      context "when credit note is finalized" do
        let(:status) { :finalized }

        it "sends the email successfully" do
          expect do
            result = service.call
            expect(result).to be_success
          end.to have_enqueued_mail(CreditNoteMailer, :created)
        end
      end

      context "when credit note is draft" do
        let(:status) { :draft }

        it "returns a not allowed failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("credit_note_not_finalized")
        end
      end
    end

    context "with a payment receipt" do
      let(:invoice) { create(:invoice, organization:, customer:, status: :finalized) }
      let(:payment) { create(:payment, payable: invoice) }
      let(:resource) { create(:payment_receipt, payment:, organization:) }

      it "sends the email successfully without status check" do
        expect do
          result = service.call
          expect(result).to be_success
        end.to have_enqueued_mail(PaymentReceiptMailer, :created)
      end

      context "when the payment's payable no longer exists" do
        before { payment.update_columns(payable_id: SecureRandom.uuid) } # rubocop:disable Rails/SkipsModelValidations

        it "returns a not allowed failure without generating or enqueueing anything" do
          allow(PaymentReceipts::GeneratePdfService).to receive(:new)

          result = nil
          expect { result = service.call }.not_to have_enqueued_mail(PaymentReceiptMailer, :created)

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("payable_not_found")
          expect(PaymentReceipts::GeneratePdfService).not_to have_received(:new)
        end
      end
    end
  end
end
