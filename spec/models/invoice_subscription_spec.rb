# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoiceSubscription, type: :model do
  let(:invoice_subscription) do
    create(
      :invoice_subscription,
      from_datetime:,
      to_datetime:,
      charges_from_datetime:,
      charges_to_datetime:,
    )
  end

  let(:invoice) { invoice_subscription.invoice }
  let(:subscription) { invoice_subscription.subscription }

  let(:from_datetime) { '2022-01-01 00:00:00' }
  let(:to_datetime) { '2022-01-31 23:59:59' }
  let(:charges_from_datetime) { '2022-01-01 00:00:00' }
  let(:charges_to_datetime) { '2022-01-31 23:59:59' }

  describe '#fees' do
    it 'returns corresponding fees' do
      first_fee = create(:fee, subscription_id: subscription.id, invoice_id: invoice.id)
      create(:fee, subscription_id: subscription.id)
      create(:fee, invoice_id: invoice.id)

      expect(invoice_subscription.fees).to eq([first_fee])
    end
  end

  describe '#charge_amount_cents' do
    it 'returns the sum of the related charge fees' do
      charge = create(:standard_charge)
      create(
        :charge_fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge:,
        amount_cents: 100,
      )

      create(
        :charge_fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge:,
        amount_cents: 200,
      )

      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        amount_cents: 400,
      )

      expect(invoice_subscription.charge_amount_cents).to eq(300)
    end
  end

  describe '#subscription_amount_cents' do
    it 'returns the amount of the subscription fees' do
      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        amount_cents: 50,
      )

      create(
        :charge_fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge: create(:standard_charge),
        amount_cents: 200,
      )

      expect(invoice_subscription.subscription_amount_cents).to eq(50)
    end
  end

  describe '#total_amount_cents' do
    it 'returns the sum of the related fees' do
      charge = create(:standard_charge)
      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        amount_cents: 50,
      )

      create(
        :charge_fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge:,
        amount_cents: 200,
      )

      create(
        :charge_fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge:,
        amount_cents: 100,
      )

      expect(invoice_subscription.total_amount_cents).to eq(350)
    end
  end

  describe '#total_amount_currency' do
    it 'returns the currency of the total amount' do
      expect(invoice_subscription.total_amount_currency).to eq(subscription.plan.amount_currency)
    end
  end

  describe '#charge_amount_currency' do
    it 'returns the currency of the charge amount' do
      expect(invoice_subscription.charge_amount_currency).to eq(subscription.plan.amount_currency)
    end
  end

  describe '#subscription_amount_currency' do
    it 'returns the currency of the subscription amount' do
      expect(invoice_subscription.subscription_amount_currency).to eq(subscription.plan.amount_currency)
    end
  end
end
