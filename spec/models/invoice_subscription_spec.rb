# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoiceSubscription, type: :model do
  let(:invoice_subscription) { create(:invoice_subscription) }
  let(:invoice) { invoice_subscription.invoice }
  let(:subscription) { invoice_subscription.subscription }

  describe '#fees' do
    it 'returns corresponding fees' do
      first_fee = create(:fee, subscription_id: subscription.id, invoice_id: invoice.id)
      second_fee = create(:fee, subscription_id: subscription.id)
      third_fee = create(:fee, invoice_id: invoice.id)

      expect(invoice_subscription.fees).to eq([first_fee])
    end
  end

  describe '#from_date' do
    it 'returns first fee from_date' do
      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        properties: { from_date: "2022-01-01" }
      )

      expect(invoice_subscription.from_date).to eq(Date.parse("2022-01-01"))
    end

    context 'when fees are empty' do
      it 'returns nil' do
        expect(invoice_subscription.from_date).to be_nil
      end
    end
  end

  describe '#to_date' do
    it 'returns first fee to_date' do
      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        properties: { to_date: "2022-01-31" }
      )

      expect(invoice_subscription.to_date).to eq(Date.parse("2022-01-31"))
    end

    context 'when fees are empty' do
      it 'returns nil' do
        expect(invoice_subscription.to_date).to be_nil
      end
    end
  end

  describe '#charge_amount_cents' do
    it 'returns the sum of the related charge fees' do
      charge = create(:standard_charge)
      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge: charge,
        amount_cents: 100
      )

      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge: charge,
        amount_cents: 200
      )

      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        amount_cents: 400
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
        amount_cents: 50
      )

      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge: create(:standard_charge),
        amount_cents: 200
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
        amount_cents: 50
      )

      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge: charge,
        amount_cents: 200
      )

      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge: charge,
        amount_cents: 100
      )

      expect(invoice_subscription.total_amount_cents).to eq(350)
    end
  end
end
