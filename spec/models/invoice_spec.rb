# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoice, type: :model do
  describe 'sequential_id' do
    let(:customer) { create(:customer) }

    let(:invoice) do
      build(
        :invoice,
        customer: customer,
      )
    end

    it 'assigns a sequential id to a new invoice' do
      invoice.save

      aggregate_failures do
        expect(invoice).to be_valid
        expect(invoice.sequential_id).to eq(1)
      end
    end

    context 'when sequential_id is present' do
      before { invoice.sequential_id = 3 }

      it 'does not replace the sequential_id' do
        invoice.save

        aggregate_failures do
          expect(invoice).to be_valid
          expect(invoice.sequential_id).to eq(3)
        end
      end
    end

    context 'when invoice alrady exists' do
      before do
        create(
          :invoice,
          customer: customer,
          sequential_id: 5,
        )
      end

      it 'takes the next available id' do
        invoice.save

        aggregate_failures do
          expect(invoice).to be_valid
          expect(invoice.sequential_id).to eq(6)
        end
      end
    end

    context 'with invoices on other organization' do
      before do
        create(
          :invoice,
          sequential_id: 1,
        )
      end

      it 'scopes the sequence to the organization' do
        invoice.save

        aggregate_failures do
          expect(invoice).to be_valid
          expect(invoice.sequential_id).to eq(1)
        end
      end
    end
  end

  describe 'number' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization: organization) }
    let(:subscription) { create(:subscription, organization: organization, customer: customer) }
    let(:invoice) { build(:invoice, customer: customer) }

    it 'generates the invoice number' do
      invoice.save
      organization_id_substring = organization.id.last(4).upcase

      expect(invoice.number).to eq("LAG-#{organization_id_substring}-001-001")
    end
  end

  describe '#charge_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization: organization) }
    let(:subscription) { create(:subscription, organization: organization, customer: customer) }
    let(:invoice) { create(:invoice, customer: customer) }
    let(:fees) { create_list(:fee, 3, invoice: invoice) }

    it 'returns the charges amount' do
      expect(invoice.charge_amount.to_s).to eq('0.00')
    end
  end

  describe '#credit_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization: organization) }
    let(:subscription) { create(:subscription, organization: organization, customer: customer) }
    let(:invoice) { create(:invoice, customer: customer) }
    let(:credit) { create(:credit, invoice: invoice) }

    it 'returns the credits amount' do
      expect(invoice.credit_amount.to_s).to eq('0.00')
    end
  end

  describe '#wallet_transaction_amount' do
    let(:customer) { create(:customer) }
    let(:invoice) { create(:invoice, customer: customer) }
    let(:wallet) { create(:wallet, customer: customer, balance: 10.0, credits_balance: 10.0) }
    let(:wallet_transaction) do
      create(:wallet_transaction, invoice: invoice, wallet: wallet, amount: 1, credit_amount: 1)
    end

    before { wallet_transaction }

    it 'returns the wallet transaction amount' do
      expect(invoice.wallet_transaction_amount.to_s).to eq('1.00')
    end
  end

  describe '#subtotal_before_prepaid_credits' do
    let(:customer) { create(:customer) }
    let(:invoice) { create(:invoice, customer: customer, amount_cents: 555) }
    let(:wallet) { create(:wallet, customer: customer, balance: 10.0, credits_balance: 10.0) }
    let(:wallet_transaction) do
      create(:wallet_transaction, invoice: invoice, wallet: wallet, amount: 1, credit_amount: 1)
    end

    before { wallet_transaction }

    it 'returns the subtotal before prepaid credits' do
      expect(invoice.subtotal_before_prepaid_credits.to_s).to eq('6.55')
    end

    context 'when there is no prepaid credits' do
      let(:wallet_transaction) { create(:wallet_transaction, wallet: wallet, amount: 1, credit_amount: 1) }

      it 'returns the invoice amount' do
        expect(invoice.subtotal_before_prepaid_credits.to_s).to eq('5.55')
      end
    end
  end

  describe '#subscription_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization: organization) }
    let(:subscription) { create(:subscription, organization: organization, customer: customer) }
    let(:invoice) { create(:invoice, customer: customer) }
    let(:fees) { create_list(:fee, 2, invoice: invoice) }

    it 'returns the subscriptions amount' do
      create(:fee, invoice: invoice, amount_cents: 200)
      create(:fee, invoice: invoice, amount_cents: 100)
      create(:fee, invoice: invoice, charge_id: create(:standard_charge).id, fee_type: 'charge')

      expect(invoice.subscription_amount.to_s).to eq('3.00')
    end
  end

  describe '#invoice_subscription' do
    let(:invoice_subscription) { create(:invoice_subscription) }

    it 'returns the invoice_subscription for the given subscription id' do
      invoice = invoice_subscription.invoice
      subscription = invoice_subscription.subscription

      expect(invoice.invoice_subscription(subscription.id)).to eq(invoice_subscription)
    end
  end

  describe '#subscription_fees' do
    let(:invoice_subscription) { create(:invoice_subscription) }

    it 'returns the fees of the corresponding invoice_subscription' do
      invoice = invoice_subscription.invoice
      subscription = invoice_subscription.subscription
      fee = create(:fee, subscription_id: subscription.id, invoice_id: invoice.id)

      expect(invoice.subscription_fees(subscription.id)).to eq([fee])
    end
  end
end
