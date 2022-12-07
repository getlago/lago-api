# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::CreateService, type: :service do
  subject(:create_service) do
    described_class.new(
      invoice: invoice,
      items: items,
      description: nil,
      credit_amount_cents: credit_amount_cents,
      refund_amount_cents: refund_amount_cents,
    )
  end

  let(:invoice) do
    create(
      :invoice,
      amount_currency: 'EUR',
      amount_cents: 20,
      total_amount_cents: 24,
      status: :succeeded,
      vat_rate: 20,
    )
  end

  let(:fee1) { create(:fee, invoice: invoice, amount_cents: 10) }
  let(:fee2) { create(:fee, invoice: invoice, amount_cents: 10) }
  let(:credit_amount_cents) { 10 }
  let(:refund_amount_cents) { 5 }
  let(:items) do
    [
      {
        fee_id: fee1.id,
        amount_cents: 10,
      },
      {
        fee_id: fee2.id,
        amount_cents: 5,
      },
    ]
  end

  describe '.call' do
    it 'creates a credit note' do
      result = create_service.call

      aggregate_failures do
        expect(result).to be_success

        credit_note = result.credit_note
        expect(credit_note.invoice).to eq(invoice)
        expect(credit_note.customer).to eq(invoice.customer)
        expect(credit_note.issuing_date.to_s).to eq(Time.zone.today.to_s)

        expect(credit_note.total_amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.total_amount_cents).to eq(15)

        expect(credit_note.credit_amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.credit_amount_cents).to eq(10)
        expect(credit_note.balance_amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.balance_amount_cents).to eq(10)
        expect(credit_note.credit_vat_amount_cents).to eq(1)
        expect(credit_note.credit_vat_amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.credit_status).to eq('available')

        expect(credit_note.refund_amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.refund_amount_cents).to eq(5)
        expect(credit_note.refund_vat_amount_cents).to eq(0)
        expect(credit_note.refund_vat_amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.refund_status).to eq('pending')

        expect(credit_note).to be_other

        expect(credit_note.items.count).to eq(2)
        item1 = credit_note.items.order(created_at: :asc).first
        expect(item1.fee).to eq(fee1)
        expect(item1.amount_cents).to eq(10)
        expect(item1.amount_currency).to eq(invoice.amount_currency)

        item2 = credit_note.items.order(created_at: :asc).last
        expect(item2.fee).to eq(fee2)
        expect(item2.amount_cents).to eq(5)
        expect(item2.amount_currency).to eq(invoice.amount_currency)
      end
    end

    it 'calls SegmentTrackJob' do
      allow(SegmentTrackJob).to receive(:perform_later)

      credit_note = create_service.call.credit_note

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'credit_note_issued',
        properties: {
          organization_id: credit_note.organization.id,
          credit_note_id: credit_note.id,
          invoice_id: credit_note.invoice_id,
          credit_note_method: 'both',
        },
      )
    end

    it 'delivers a webhook' do
      create_service.call

      expect(SendWebhookJob).to have_been_enqueued
        .with('credit_note.created', CreditNote)
    end

    context 'with invalid items' do
      let(:credit_amount_cents) { 10 }
      let(:refund_amount_cents) { 15 }
      let(:items) do
        [
          {
            fee_id: fee1.id,
            amount_cents: 10,
          },
          {
            fee_id: fee2.id,
            amount_cents: 15,
          },
        ]
      end

      it 'returns a failed result' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:amount_cents)
          expect(result.error.messages[:amount_cents]).to eq(
            %w[
              higher_than_remaining_fee_amount
            ],
          )
        end
      end
    end

    context 'with a refund, a payment and a succeeded invoice' do
      let(:payment) { create(:payment, invoice: invoice) }

      before { payment }

      it 'enqueues a refund job' do
        create_service.call

        expect(CreditNotes::Refunds::StripeCreateJob).to have_been_enqueued
          .with(CreditNote)
      end

      context 'when Gocardless provider' do
        let(:gocardless_provider) { create(:gocardless_provider) }
        let(:gocardless_customer) { create(:gocardless_customer) }
        let(:payment) do
          create(
            :payment,
            invoice: invoice,
            payment_provider: gocardless_provider,
            payment_provider_customer: gocardless_customer,
          )
        end

        it 'enqueues a refund job' do
          create_service.call

          expect(CreditNotes::Refunds::GocardlessCreateJob).to have_been_enqueued.with(CreditNote)
        end
      end

      context 'when credit note does not have refund amount' do
        let(:credit_amount_cents) { 15 }
        let(:refund_amount_cents) { 0 }

        it 'does not enqueue a refund job' do
          expect { create_service.call }.not_to have_enqueued_job(CreditNotes::Refunds::StripeCreateJob)
        end
      end
    end

    context 'with customer timezone' do
      before { invoice.customer.update!(timezone: 'America/Los_Angeles') }

      let(:timestamp) { DateTime.parse('2022-11-25 01:00:00').to_i }

      it 'assigns the issuing date in the customer timezone' do
        travel_to(DateTime.parse('2022-11-25 01:00:00')) do
          result = create_service.call

          expect(result.credit_note.issuing_date.to_s).to eq('2022-11-24')
        end
      end
    end
  end
end
