# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::CreateService, type: :service do
  subject(:create_service) do
    described_class.new(
      invoice:,
      items:,
      description: nil,
      credit_amount_cents:,
      refund_amount_cents:,
      automatic:,
      context:
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      currency: "EUR",
      total_amount_cents: 24,
      payment_status: :succeeded,
      taxes_rate: 20,
      version_number: 2
    )
  end

  let(:tax) { create(:tax, organization:, rate: 20) }

  let(:automatic) { true }
  let(:context) { nil }
  let(:fee1) { create(:fee, invoice:, amount_cents: 10, taxes_amount_cents: 1, taxes_rate: 20) }
  let(:fee2) { create(:fee, invoice:, amount_cents: 10, taxes_amount_cents: 1, taxes_rate: 20) }
  let(:credit_amount_cents) { 12 }
  let(:refund_amount_cents) { 6 }
  let(:items) do
    [
      {
        fee_id: fee1.id,
        amount_cents: 10
      },
      {
        fee_id: fee2.id,
        amount_cents: 5
      }
    ]
  end

  before do
    create(:fee_applied_tax, tax:, fee: fee1)
    create(:fee_applied_tax, tax:, fee: fee2)
    create(:invoice_applied_tax, tax:, invoice:) if invoice
  end

  describe "#call" do
    subject(:result) { create_service.call }

    let(:credit_note) { subject.credit_note }

    it "creates a credit note" do
      result = create_service.call

      aggregate_failures do
        expect(result).to be_success

        credit_note = result.credit_note
        expect(credit_note.invoice).to eq(invoice)
        expect(credit_note.customer).to eq(invoice.customer)
        expect(credit_note.issuing_date.to_s).to eq(Time.zone.today.to_s)

        expect(credit_note.coupons_adjustment_amount_cents).to eq(0)
        expect(credit_note.taxes_amount_cents).to eq(3)
        expect(credit_note.taxes_rate).to eq(20)
        expect(credit_note.applied_taxes.count).to eq(1)

        expect(credit_note.total_amount_currency).to eq(invoice.currency)
        expect(credit_note.total_amount_cents).to eq(18)

        expect(credit_note.credit_amount_currency).to eq(invoice.currency)
        expect(credit_note.credit_amount_cents).to eq(12)
        expect(credit_note.balance_amount_currency).to eq(invoice.currency)
        expect(credit_note.balance_amount_cents).to eq(12)
        expect(credit_note.credit_status).to eq("available")

        expect(credit_note.refund_amount_currency).to eq(invoice.currency)
        expect(credit_note.refund_amount_cents).to eq(6)
        expect(credit_note.refund_status).to eq("pending")

        expect(credit_note).to be_other

        expect(credit_note.items.count).to eq(2)
        item1 = credit_note.items.order(created_at: :asc).first
        expect(item1.fee).to eq(fee1)
        expect(item1.amount_cents).to eq(10)
        expect(item1.amount_currency).to eq(invoice.currency)

        item2 = credit_note.items.order(created_at: :asc).last
        expect(item2.fee).to eq(fee2)
        expect(item2.amount_cents).to eq(5)
        expect(item2.amount_currency).to eq(invoice.currency)
      end
    end

    it "enqueues SegmentTrackJob after commit" do
      expect { subject }.to have_enqueued_job_after_commit(SegmentTrackJob).with do |params|
        expect(params).to match(membership_id: CurrentContext.membership,
          event: "credit_note_issued",
          properties: {
            organization_id: organization.id,
            credit_note_id: credit_note.id,
            invoice_id: invoice.id,
            credit_note_method: "both"
          })
      end
    end

    it "delivers a webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with do |event, job_credit_note|
        expect(event).to eq("credit_note.created")
        expect(job_credit_note).to eq(credit_note)
      end
    end

    it "enqueues a CreditNotes::GeneratePdfJob after commit" do
      expect { subject }.to have_enqueued_job_after_commit(CreditNotes::GeneratePdfJob).with do |job_credit_note|
        expect(job_credit_note).to eq(credit_note)
      end
    end

    it "delivers an email after commit" do
      expect { subject }.to have_enqueued_job_after_commit(SendEmailJob).with do |email, job_credit_note|
        expect(email).to eq(credit_note.billing_entity.email)
        expect(job_credit_note).to eq(credit_note)
      end
    end

    it "produces an activity log" do
      result = create_service.call

      expect(Utils::ActivityLog).to have_produced("credit_note.created").with(result.credit_note)
    end

    it_behaves_like "syncs credit note" do
      let(:service_call) { subject }
    end

    context "when customer has tax_provider set up" do
      let(:customer) { create(:customer, :with_tax_integration, organization:) }

      it "sync with tax provider after commit" do
        expect { subject }.to have_enqueued_job_after_commit(CreditNotes::ProviderTaxes::ReportJob).with do |**kwargs|
          expect(kwargs[:credit_note]).to eq(credit_note)
        end
      end
    end

    context "when billing_entity does not have right email settings" do
      before { invoice.billing_entity.update!(email_settings: []) }

      it "does not enqueue an SendEmailJob" do
        expect { subject }.not_to have_enqueued_job(SendEmailJob)
      end
    end

    context "with invalid items" do
      let(:credit_amount_cents) { 10 }
      let(:refund_amount_cents) { 15 }
      let(:items) do
        [
          {
            fee_id: fee1.id,
            amount_cents: 10
          },
          {
            fee_id: fee2.id,
            amount_cents: 15
          }
        ]
      end

      it "returns a failed result" do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:amount_cents)
          expect(result.error.messages[:amount_cents]).to eq(
            %w[
              higher_than_remaining_fee_amount
            ]
          )
        end
      end
    end

    context "when items are missing" do
      let(:items) {}

      it "returns a failed result" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:items)
        expect(result.error.messages[:items]).to eq(
          %w[
            must_be_an_array
          ]
        )
      end
    end

    context "with a refund, a payment and a succeeded invoice" do
      let(:payment) { create(:payment, payable: invoice) }

      before { payment }

      it "enqueues a refund job after commit" do
        expect { subject }.to have_enqueued_job_after_commit(CreditNotes::Refunds::StripeCreateJob).with do |job_credit_note|
          expect(job_credit_note).to eq(credit_note)
        end
      end

      context "when Gocardless provider" do
        let(:gocardless_provider) { create(:gocardless_provider) }
        let(:gocardless_customer) { create(:gocardless_customer) }
        let(:payment) do
          create(
            :payment,
            payable: invoice,
            payment_provider: gocardless_provider,
            payment_provider_customer: gocardless_customer
          )
        end

        it "enqueues a refund job after commit" do
          expect { subject }.to have_enqueued_job_after_commit(CreditNotes::Refunds::GocardlessCreateJob).with do |job_credit_note|
            expect(job_credit_note).to eq(credit_note)
          end
        end
      end

      context "when credit note does not have refund amount" do
        let(:credit_amount_cents) { 15 }
        let(:refund_amount_cents) { 0 }

        it "does not enqueue a refund job" do
          expect { subject }.not_to have_enqueued_job(CreditNotes::Refunds::StripeCreateJob)
        end
      end
    end

    context "with customer timezone" do
      before { invoice.customer.update!(timezone: "America/Los_Angeles") }

      let(:timestamp) { DateTime.parse("2022-11-25 01:00:00").to_i }

      it "assigns the issuing date in the customer timezone" do
        travel_to(DateTime.parse("2022-11-25 01:00:00")) do
          result = create_service.call

          expect(result.credit_note.issuing_date.to_s).to eq("2022-11-24")
        end
      end
    end

    context "when invoice is not found" do
      let(:invoice) { nil }
      let(:items) { [] }

      it "returns a failure" do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success

          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq("invoice_not_found")
        end
      end
    end

    context "when invoice is not automatic" do
      let(:automatic) { false }

      it "returns a failure" do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success

          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("feature_unavailable")
        end
      end

      context "with a valid license" do
        around { |test| lago_premium!(&test) }

        it "returns a success" do
          result = create_service.call
          expect(result).to be_success
        end

        context "when invoice is draft" do
          let(:invoice) do
            create(
              :invoice,
              :draft,
              organization:,
              customer:,
              currency: "EUR",
              fees_amount_cents: 20,
              total_amount_cents: 24,
              payment_status: :succeeded,
              taxes_rate: 20
            )
          end

          it "creates a draft credit note" do
            result = create_service.call

            aggregate_failures do
              expect(result).to be_success
              expect(result.credit_note).to be_draft
            end
          end

          it "does not deliver a webhook" do
            create_service.call
            expect(SendWebhookJob).not_to have_been_enqueued.with("credit_note.created", CreditNote)
          end

          it "does not call SegmentTrackJob" do
            expect { subject }.not_to have_enqueued_job(SegmentTrackJob)
          end
        end

        context "when invoice is legacy" do
          let(:invoice) do
            create(
              :invoice,
              currency: "EUR",
              sub_total_excluding_taxes_amount_cents: 20,
              total_amount_cents: 24,
              payment_status: :succeeded,
              taxes_rate: 20,
              version_number: 1
            )
          end

          it "returns a failure" do
            result = create_service.call

            aggregate_failures do
              expect(result).not_to be_success

              expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
              expect(result.error.code).to eq("invalid_type_or_status")
            end
          end
        end
      end
    end

    context "when invoice is v3 with coupons" do
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: "EUR",
          fees_amount_cents: 20,
          coupons_amount_cents: 10,
          taxes_amount_cents: 2,
          total_amount_cents: 12,
          payment_status: :succeeded,
          taxes_rate: 20,
          version_number: 3
        )
      end

      let(:fee1) do
        create(:fee, invoice:, amount_cents: 10, taxes_amount_cents: 1, taxes_rate: 20, precise_coupons_amount_cents: 5)
      end

      let(:fee2) do
        create(:fee, invoice:, amount_cents: 10, taxes_amount_cents: 1, taxes_rate: 20, precise_coupons_amount_cents: 5)
      end

      let(:credit_amount_cents) { 6 }
      let(:refund_amount_cents) { 3 }
      let(:items) do
        [
          {
            fee_id: fee1.id,
            amount_cents: 10
          },
          {
            fee_id: fee2.id,
            amount_cents: 5
          }
        ]
      end

      it "takes coupons amount into account" do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          credit_note = result.credit_note
          expect(credit_note).to have_attributes(
            invoice:,
            customer: invoice.customer,
            currency: invoice.currency,
            credit_status: "available",
            refund_status: "pending",
            reason: "other",
            total_amount_cents: 9,
            credit_amount_cents: 6,
            refund_amount_cents: 3,
            balance_amount_cents: 6,
            coupons_adjustment_amount_cents: 8,
            taxes_amount_cents: 2,
            taxes_rate: 20
          )
          expect(credit_note.applied_taxes.count).to eq(1)

          expect(credit_note.items.count).to eq(2)

          item1 = credit_note.items.order(created_at: :asc).first
          expect(item1).to have_attributes(
            fee: fee1,
            amount_cents: 10,
            amount_currency: invoice.currency
          )

          item2 = credit_note.items.order(created_at: :asc).last
          expect(item2).to have_attributes(
            fee: fee2,
            amount_cents: 5,
            amount_currency: invoice.currency
          )
        end
      end
    end

    context "when invoice is credit" do
      let(:invoice) do
        create(
          :invoice,
          :credit,
          organization:,
          customer:,
          currency: "EUR",
          fees_amount_cents: 1000,
          total_amount_cents: 1000,
          payment_status: :succeeded
        )
      end
      let(:wallet) { create :wallet, customer:, balance_cents: 1000, rate_amount:, credits_balance: 1 }
      let(:rate_amount) { 10 }
      let(:wallet_transaction) { create :wallet_transaction, wallet: }
      let(:fee) { create :fee, invoice:, fee_type: :credit, invoiceable: wallet_transaction, amount_cents: 1000 }
      let(:credit_amount_cents) { 0 }
      let(:refund_amount_cents) { 1000 }
      let(:items) do
        [
          {
            fee_id: fee.id,
            amount_cents: 1000
          }
        ]
      end
      let(:automatic) { false }

      before do
        wallet
        fee
      end

      around { |test| lago_premium!(&test) }

      it "Creates credit note and voids corresponding amount of credits from the wallet" do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          credit_note = result.credit_note
          expect(credit_note.refund_amount_cents).to eq(1000)
          wallet_transaction = wallet.wallet_transactions.order(:created_at).last
          # we're refunding 10_00 cents -> 10 euros, the rate of the wallet, 1 credit = 10 euros, so amount credits
          # in the transaction is 1, while the "money" amount is 10
          expect(wallet_transaction.credit_amount).to eq(1)
          expect(wallet_transaction.amount).to eq(10)
          expect(wallet_transaction.transaction_status).to eq("voided")
          expect(wallet_transaction.transaction_type).to eq("outbound")
          expect(wallet.reload.balance_cents).to eq(0)
        end
      end

      context "with different rate amount" do
        let(:rate_amount) { 20 }

        it "calculates correct credits amount" do
          result = create_service.call

          aggregate_failures do
            expect(result).to be_success

            credit_note = result.credit_note
            expect(credit_note.refund_amount_cents).to eq(1000)
            wallet_transaction = wallet.wallet_transactions.order(:created_at).last
            expect(wallet_transaction.credit_amount).to eq(0.5)
            expect(wallet_transaction.amount).to eq(10)
          end
        end
      end

      context "when wallet is terminated" do
        let(:wallet) { create :wallet, customer:, balance_cents: 1000, rate_amount:, status: :terminated }

        it "returns error" do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success

            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
            expect(result.error.code).to eq("invalid_type_or_status")
          end
        end
      end

      context "when associated wallet balance is less than requested sum" do
        let(:wallet) { create :wallet, customer:, balance_cents: 500, rate_amount: }

        it "returns error" do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success

            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages.keys).to include(:amount_cents)
          end
        end
      end

      context "when creating credit_note with credit amount" do
        let(:credit_amount_cents) { 10 }

        it "returns error" do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success

            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages.keys).to include(:credit_amount_cents)
          end
        end
      end
    end

    context "when invoice is voided" do
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: "EUR",
          fees_amount_cents: 1000,
          total_amount_cents: 1000,
          payment_status: :succeeded,
          status: :voided
        )
      end

      it "creates a credit note with finalized status instead of voided" do
        result = create_service.call
        expect(result).to be_success

        credit_note = result.credit_note
        expect(credit_note.invoice).to eq(invoice)
        expect(credit_note.status).to eq("finalized")
        expect(invoice.status).to eq("voided")
      end
    end

    context "when 'preview' context provided" do
      let(:context) { :preview }

      it "builds a credit note" do
        expect(result).to be_success

        credit_note = result.credit_note
        expect(credit_note).to be_a(CreditNote).and be_new_record
        expect(credit_note.invoice).to eq(invoice)
        expect(credit_note.customer).to eq(invoice.customer)
        expect(credit_note.issuing_date.to_s).to eq(Time.zone.today.to_s)

        expect(credit_note.coupons_adjustment_amount_cents).to eq(0)
        expect(credit_note.taxes_amount_cents).to eq(3)
        expect(credit_note.taxes_rate).to eq(20)
        expect(credit_note.applied_taxes.size).to eq(1)

        expect(credit_note.total_amount_currency).to eq(invoice.currency)
        expect(credit_note.total_amount_cents).to eq(18)

        expect(credit_note.credit_amount_currency).to eq(invoice.currency)
        expect(credit_note.credit_amount_cents).to eq(12)
        expect(credit_note.balance_amount_currency).to eq(invoice.currency)
        expect(credit_note.balance_amount_cents).to eq(12)
        expect(credit_note.credit_status).to eq("available")

        expect(credit_note.refund_amount_currency).to eq(invoice.currency)
        expect(credit_note.refund_amount_cents).to eq(6)
        expect(credit_note.refund_status).to eq("pending")

        expect(credit_note).to be_other

        expect(credit_note.items.size).to eq(2)
        expect(credit_note.items).to all be_new_record

        item1 = credit_note.items.first
        expect(item1.fee).to eq(fee1)
        expect(item1.amount_cents).to eq(10)
        expect(item1.amount_currency).to eq(invoice.currency)

        item2 = credit_note.items.second
        expect(item2.fee).to eq(fee2)
        expect(item2.amount_cents).to eq(5)
        expect(item2.amount_currency).to eq(invoice.currency)
      end

      it "does not persist any credit note" do
        expect { subject }.not_to change(CreditNote, :count)
      end

      it "does not persist any credit note item" do
        expect { subject }.not_to change(CreditNoteItem, :count)
      end

      it "does not call SegmentTrackJob" do
        expect { subject }.not_to have_enqueued_job(SegmentTrackJob)
      end

      it "does not deliver a webhook" do
        subject

        expect(SendWebhookJob).not_to have_been_enqueued.with("credit_note.created", CreditNote)
        expect(CreditNotes::GeneratePdfJob).not_to have_been_enqueued
      end

      it "does not send an email" do
        expect { subject }.not_to have_enqueued_job(SendEmailJob)
      end
    end
  end
end
