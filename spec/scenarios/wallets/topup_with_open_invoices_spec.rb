# frozen_string_literal: true

require 'rails_helper'

describe 'Wallet Transaction with invoice after payment', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  around { |test| lago_premium!(&test) }

  context 'when the wallet does not require successful payment before invoicing' do
    it 'allows wallet transaction to require successful payment' do
      create_wallet({
        external_customer_id: customer.external_id,
        rate_amount: '1',
        name: 'Wallet1',
        currency: 'EUR',
        granted_credits: '10',
        invoice_requires_successful_payment: false # default
      })

      wallet = customer.wallets.sole

      expect(wallet.credits_balance).to eq 10

      create_wallet_transaction({
        wallet_id: wallet.id,
        paid_credits: '15',
        invoice_requires_successful_payment: true
      })
      wt = WalletTransaction.find json[:wallet_transactions].first[:lago_id]

      expect(wt.status).to eq 'pending'
      expect(wt.transaction_status).to eq 'purchased'
      expect(wt.invoice_requires_successful_payment).to be true

      # Customer does not have a payment_provider set yet
      invoice = customer.invoices.credit.sole
      expect(invoice.status).to eq 'open'
      expect(invoice.payment_status).to eq 'pending'
      expect(invoice.number).to end_with '-DRAFT'
      expect(invoice.total_amount_cents).to eq 1500
      expect(invoice.file?).to be false

      setup_stripe_for(customer:)

      allow_any_instance_of(::Invoices::Payments::StripeService).to receive(:create_payment_intent) # rubocop:disable RSpec/AnyInstance
        .and_return(
          Stripe::PaymentIntent.construct_from(
            id: "ch_#{SecureRandom.hex(6)}",
            status: :succeeded,
            amount: invoice.total_amount_cents,
            currency: invoice.currency
          )
        )
      Invoices::Payments::CreateService.call(invoice)
      perform_all_enqueued_jobs

      invoice.reload
      expect(invoice.status).to eq 'finalized'
      expect(invoice.payment_status).to eq 'succeeded'
      expect(invoice.number).to end_with '-001-001'
      expect(invoice.file?).to be true

      wt.reload
      expect(wt.status).to eq 'settled'
      expect(wt.settled_at).not_to be_nil

      wallet.reload
      expect(wallet.credits_balance).to eq 25
    end

    context 'when there is a payment failure' do
      it 'keeps the invoice invisible' do
        setup_stripe_for(customer:)
        allow_any_instance_of(::Invoices::Payments::StripeService).to receive(:create_payment_intent) # rubocop:disable RSpec/AnyInstance
          .and_return(
            Stripe::PaymentIntent.construct_from(
              id: "ch_#{SecureRandom.hex(6)}",
              status: :failed,
              amount: 1500,
              currency: 'EUR'
            )
          )

        create_wallet({
          external_customer_id: customer.external_id,
          rate_amount: '1',
          name: 'Wallet1',
          currency: 'EUR',
          granted_credits: '10',
          invoice_requires_successful_payment: false # default
        })
        wallet = customer.wallets.sole

        create_wallet_transaction({
          wallet_id: wallet.id,
          paid_credits: '15',
          invoice_requires_successful_payment: true
        })
        wt = WalletTransaction.find json[:wallet_transactions].first[:lago_id]

        # Customer does not have a payment_provider set yet
        invoice = customer.invoices.credit.sole
        expect(invoice.status).to eq 'open'
        expect(invoice.payment_status).to eq 'failed'
        expect(invoice.number).to end_with '-DRAFT'
        expect(invoice.file?).to be false

        wt.reload
        expect(wt.status).to eq 'pending'
        expect(wt.settled_at).to be_nil

        wallet.reload
        expect(wallet.credits_balance).to eq 10
      end
    end
  end
end
