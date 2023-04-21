# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoice, type: :model do
  subject(:invite) { create(:invite) }

  it_behaves_like 'paper_trail traceable'

  describe 'sequential_id' do
    let(:customer) { create(:customer) }
    let(:invoice) { build(:invoice, customer:) }

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
        create(:invoice, customer:, sequential_id: 5)
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
        create(:invoice, sequential_id: 1)
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
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:invoice) { build(:invoice, customer:) }

    it 'generates the invoice number' do
      invoice.save
      organization_id_substring = organization.id.last(4).upcase

      expect(invoice.number).to eq("LAG-#{organization_id_substring}-001-001")
    end
  end

  describe '#currency' do
    let(:invoice) { build(:invoice, currency: 'JPY') }

    it { expect(invoice.currency).to eq('JPY') }
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

  describe '#fee_total_amount_cents' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, customer:, organization:) }

    it 'returns the fee amount vat included' do
      create(:fee, invoice:, amount_cents: 100, vat_rate: 20)
      create(:fee, invoice:, amount_cents: 133, vat_rate: 20)

      expect(invoice.fee_total_amount_cents).to eq(120 + 160)
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
    let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }
    let(:fee) { create(:charge_fee, subscription:, invoice:, charge:) }

    it 'returns the fees of the corresponding invoice_subscription' do
      expect(invoice.recurring_fees(subscription.id)).to eq([fee])
    end
  end

  describe '#recurring_breakdown' do
    let(:invoice_subscription) { create(:invoice_subscription) }
    let(:invoice) { invoice_subscription.invoice }
    let(:subscription) { invoice_subscription.subscription }
    let(:billable_metric) { create(:recurring_billable_metric, organization: subscription.organization) }
    let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }
    let(:fee) { create(:charge_fee, subscription:, invoice:, charge:) }

    it 'returns the fees of the corresponding invoice_subscription' do
      expect(invoice.recurring_breakdown(fee)).to eq([])
    end
  end

  describe '#creditable_amount_cents' do
    context 'when invoice v1' do
      it 'returns 0' do
        invoice = build(:invoice, version_number: 1)
        expect(invoice.creditable_amount_cents).to eq(0)
      end
    end

    context 'when credit' do
      it 'returns 0' do
        invoice = build(:invoice, :credit)
        expect(invoice.creditable_amount_cents).to eq(0)
      end
    end

    context 'when draft' do
      it 'returns 0' do
        invoice = build(:invoice, :draft)
        expect(invoice.creditable_amount_cents).to eq(0)
      end
    end

    context 'when fees sum is zero' do
      let(:invoice_subscription) { create(:invoice_subscription) }
      let(:invoice) { invoice_subscription.invoice }
      let(:subscription) { invoice_subscription.subscription }
      let(:billable_metric) { create(:recurring_billable_metric, organization: subscription.organization) }
      let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }

      before do
        create(:charge_fee, subscription:, invoice:, charge:, amount_cents: 0, vat_rate: 20)
      end

      it 'returns 0' do
        expect(invoice.creditable_amount_cents).to eq(0)
      end
    end

    it 'returns the expected creditable amount in cents' do
      invoice = create(:invoice, version_number: 2)
      invoice_subscription = create(:invoice_subscription, invoice:)
      subscription = invoice_subscription.subscription
      billable_metric = create(:recurring_billable_metric, organization: subscription.organization)
      charge = create(:standard_charge, plan: subscription.plan, billable_metric:)
      create(:charge_fee, subscription:, invoice:, charge:, amount_cents: 133, vat_rate: 20)

      expect(invoice.creditable_amount_cents).to eq(160)
    end

    context 'when invoice v3 with coupons' do
      let(:invoice) do
        create(
          :invoice,
          fees_amount_cents: 200,
          coupons_amount_cents: 20,
          vat_amount_cents: 36,
          total_amount_cents: 216,
          vat_rate: 20,
          version_number: 3,
        )
      end

      let(:invoice_subscription) { create(:invoice_subscription, invoice:) }
      let(:subscription) { invoice_subscription.subscription }
      let(:billable_metric) do
        create(:recurring_billable_metric, organization: subscription.organization)
      end
      let(:charge) do
        create(:standard_charge, plan: subscription.plan, billable_metric:)
      end
      let(:fee) do
        create(:charge_fee, subscription:, invoice:, charge:, amount_cents: 200, vat_rate: 20)
      end

      before { fee }

      it 'returns the expected creditable amount in cents' do
        expect(invoice.creditable_amount_cents).to eq(216)
      end
    end
  end
end
