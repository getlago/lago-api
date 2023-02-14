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

  describe '#currency' do
    let(:invoice) { build(:invoice, amount_currency: 'JPY') }

    it { expect(invoice.currency).to eq('JPY') }
  end

  describe '#sub_total_vat_excluded_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:invoice) { create(:invoice, customer:, amount_currency: 'EUR', organization:) }
    let(:fees) { create_list(:fee, 3, invoice:, amount_cents: 300) }

    before { fees }

    it 'returns the sub total amount without VAT' do
      expect(invoice.sub_total_vat_excluded_amount.to_s).to eq('9.00')
    end
  end

  describe '#sub_total_vat_included_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization:, vat_rate: 20) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:invoice) { create(:invoice, customer:, amount_currency: 'EUR', vat_amount_cents: 180, organization:) }
    let(:fees) { create_list(:fee, 3, invoice:, amount_cents: 300) }

    before { fees }

    it 'returns the sub total amount with VAT' do
      expect(invoice.sub_total_vat_included_amount.to_s).to eq('10.80')
    end
  end

  describe '#coupon_total_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:credit) { create(:credit, invoice:) }

    before { credit }

    it 'returns the coupon amount' do
      expect(invoice.coupon_total_amount.to_s).to eq('2.00')
    end
  end

  describe '#credit_note_total_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:credit) { create(:credit_note_credit, invoice:) }

    before { credit }

    it 'returns the credit note amount' do
      expect(invoice.credit_note_total_amount.to_s).to eq('2.00')
    end
  end

  describe '#charge_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:fees) { create_list(:fee, 3, invoice:) }

    it 'returns the charges amount' do
      expect(invoice.charge_amount.to_s).to eq('0.00')
    end
  end

  describe '#credit_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:credit) { create(:credit, invoice:) }

    it 'returns the credits amount' do
      expect(invoice.credit_amount.to_s).to eq('0.00')
    end
  end

  describe '#wallet_transaction_amount' do
    let(:customer) { create(:customer) }
    let(:invoice) { create(:invoice, customer:, organization: customer.organization) }
    let(:wallet) { create(:wallet, customer:, balance: 10.0, credits_balance: 10.0) }
    let(:wallet_transaction) do
      create(:wallet_transaction, invoice:, wallet:, amount: 1, credit_amount: 1)
    end

    before { wallet_transaction }

    it 'returns the wallet transaction amount' do
      expect(invoice.wallet_transaction_amount.to_s).to eq('1.00')
    end
  end

  describe '#subtotal_before_prepaid_credits' do
    let(:customer) { create(:customer) }
    let(:invoice) { create(:invoice, customer:, amount_cents: 555, organization: customer.organization) }
    let(:wallet) { create(:wallet, customer:, balance: 10.0, credits_balance: 10.0) }
    let(:wallet_transaction) do
      create(:wallet_transaction, invoice:, wallet:, amount: 1, credit_amount: 1)
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

  describe '#fee_total_amount_cents' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:fees) { create_list(:fee, 2, invoice:, amount_cents: 100, vat_rate: 20, vat_amount_cents: 20) }

    before { fees }

    it 'returns the fee amount vat included' do
      expect(invoice.fee_total_amount_cents).to eq(240)
    end
  end

  describe '#subscription_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:fees) { create_list(:fee, 2, invoice:) }

    it 'returns the subscriptions amount' do
      create(:fee, invoice:, amount_cents: 200)
      create(:fee, invoice:, amount_cents: 100)
      create(:fee, invoice:, charge_id: create(:standard_charge).id, fee_type: 'charge')

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

  describe '#recurring_fees' do
    let(:invoice_subscription) { create(:invoice_subscription) }
    let(:invoice) { invoice_subscription.invoice }
    let(:subscription) { invoice_subscription.subscription }
    let(:billable_metric) { create(:recurring_billable_metric, organization: subscription.organization) }
    let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric: billable_metric) }
    let(:fee) { create(:charge_fee, subscription: subscription, invoice: invoice, charge: charge) }

    it 'returns the fees of the corresponding invoice_subscription' do
      expect(invoice.recurring_fees(subscription.id)).to eq([fee])
    end
  end

  describe '#recurring_breakdown' do
    let(:invoice_subscription) { create(:invoice_subscription) }
    let(:invoice) { invoice_subscription.invoice }
    let(:subscription) { invoice_subscription.subscription }
    let(:billable_metric) { create(:recurring_billable_metric, organization: subscription.organization) }
    let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric: billable_metric) }
    let(:fee) { create(:charge_fee, subscription: subscription, invoice: invoice, charge: charge) }

    it 'returns the fees of the corresponding invoice_subscription' do
      expect(invoice.recurring_breakdown(fee)).to eq([])
    end
  end
end
