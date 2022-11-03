# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::Refunds::StripeService, type: :service do
  subject(:stripe_service) { described_class.new(credit_note) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:stripe_payment_provider) { create(:stripe_provider, organization: organization) }
  let(:stripe_customer) { create(:stripe_customer, customer: customer) }
  let(:payment) do
    create(
      :payment,
      payment_provider: stripe_payment_provider,
      payment_provider_customer: stripe_customer,
      amount_cents: 200,
      amount_currency: 'CHF',
      invoice: credit_note.invoice,
    )
  end

  let(:credit_note) do
    create(
      :credit_note,
      customer: customer,
      refund_amount_cents: 134,
      refund_amount_currency: 'CHF',
      refund_status: :pending,
    )
  end

  describe '#create' do
    before do
      payment

      allow(Stripe::Refund).to receive(:create)
        .and_return(
          Stripe::Refund.construct_from(
            id: 're_123456',
            status: 'succeeded',
            amount: 134,
            currency: 'chf',
          ),
        )
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates a stripe refund and a refund' do
      result = stripe_service.create

      aggregate_failures do
        expect(result).to be_success

        expect(result.refund.id).to be_present

        expect(result.refund.credit_note).to eq(credit_note)
        expect(result.refund.payment).to eq(payment)
        expect(result.refund.payment_provider).to eq(stripe_payment_provider)
        expect(result.refund.payment_provider_customer).to eq(stripe_customer)
        expect(result.refund.amount_cents).to eq(134)
        expect(result.refund.amount_currency).to eq('CHF')
        expect(result.refund.status).to eq('succeeded')
        expect(result.refund.provider_refund_id).to eq('re_123456')

        expect(result.credit_note).to be_succeeded
      end
    end

    it 'call SegmentTrackJob' do
      stripe_service.create

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'refund_status_change',
        properties: {
          organization_id: credit_note.organization.id,
          credit_note_id: credit_note.id,
          refund_status: 'succeeded',
        },
      )
    end

    context 'with an error on stripe' do
      before do
        allow(Stripe::Refund).to receive(:create)
          .and_raise(Stripe::InvalidRequestError.new('error', {}))
      end

      it 'delivers an error webhook' do
        expect { stripe_service.create }
          .to raise_error(Stripe::InvalidRequestError)

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            'credit_note.provider_refund_failure',
            credit_note,
            provider_customer_id: stripe_customer.provider_customer_id,
            provider_error: {
              message: 'error',
              error_code: nil,
            },
          )
      end
    end

    context 'when credit note does not have a refund amount' do
      let(:credit_note) do
        create(
          :credit_note,
          customer: customer,
          refund_amount_cents: 0,
          refund_amount_currency: 'CHF',
        )
      end

      it 'does not create a refund' do
        result = stripe_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.credit_note).to eq(credit_note)
          expect(result.refund).to be_nil

          expect(Stripe::Refund).not_to have_received(:create)
        end
      end
    end

    context 'when invoice does not have a payment' do
      let(:payment) { nil }

      it 'does not create a refund' do
        result = stripe_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.credit_note).to eq(credit_note)
          expect(result.refund).to be_nil

          expect(Stripe::Refund).not_to have_received(:create)
        end
      end
    end
  end

  describe '#update_status' do
    let(:refund) do
      create(:refund, credit_note: credit_note)
    end

    before { credit_note.pending! }

    it 'updates the refund status' do
      result = stripe_service.update_status(
        provider_refund_id: refund.provider_refund_id,
        status: 'succeeded',
      )

      aggregate_failures do
        expect(result).to be_success

        expect(result.refund).to eq(refund)
        expect(result.refund.status).to eq('succeeded')

        expect(result.credit_note).to be_succeeded
      end
    end

    it 'calls SegmentTrackJob' do
      allow(SegmentTrackJob).to receive(:perform_later)

      stripe_service.update_status(
        provider_refund_id: refund.provider_refund_id,
        status: 'succeeded',
      )

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'refund_status_change',
        properties: {
          organization_id: credit_note.organization.id,
          credit_note_id: credit_note.id,
          refund_status: 'succeeded',
        },
      )
    end

    context 'when refund is not found' do
      it 'fails' do
        result = stripe_service.update_status(
          provider_refund_id: 'foo',
          status: 'succeeded',
        )

        aggregate_failures do
          expect(result).not_to be_success

          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq('stripe_refund')
        end
      end
    end

    context 'when status is not valid' do
      it 'fails' do
        result = stripe_service.update_status(
          provider_refund_id: refund.provider_refund_id,
          status: 'invalid',
        )

        aggregate_failures do
          expect(result).not_to be_success

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:refund_status]).to include('value_is_invalid')
        end
      end
    end

    context 'when status is failed' do
      before { stripe_customer }

      it 'delivers an error webhook' do
        result = stripe_service.update_status(
          provider_refund_id: refund.provider_refund_id,
          status: 'failed',
        )

        aggregate_failures do
          expect(result).not_to be_success

          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('refund_failed')
          expect(result.error.error_message).to eq('Refund failed to perform')

          expect(SendWebhookJob).to have_been_enqueued
            .with(
              'credit_note.provider_refund_failure',
              credit_note,
              provider_customer_id: stripe_customer.provider_customer_id,
              provider_error: {
                message: 'Payment refund failed',
                error_code: nil,
              },
            )
        end
      end
    end
  end
end
