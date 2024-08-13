# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::CreateFromUsageThresholdService, type: :service do
  subject(:create_service) { described_class.new(usage_threshold:, invoice:, amount_cents:) }

  let(:usage_threshold) { create(:usage_threshold, plan:) }
  let(:invoice) { create(:invoice, organization: customer.organization, customer:) }

  let(:invoice_subscription) { create(:invoice_subscription, invoice:, subscription:) }
  let(:customer) { create(:customer) }
  let(:plan) { create(:plan, organization: customer.organization) }
  let(:subscription) { create(:subscription, plan:, customer:) }

  let(:amount_cents) { 1000 }

  let(:tax) { create(:tax, organization: customer.organization, rate: 20) }

  before do
    invoice_subscription
    tax
  end

  it 'creates a fee from usage threshold', aggregate_failure: true do
    fee_result = create_service.call

    expect(fee_result).to be_success
    expect(fee_result.fee).to be_present

    fee = fee_result.fee
    expect(fee).to be_persisted
    expect(fee).to have_attributes(
      subscription:,
      invoice:,
      usage_threshold:,
      invoiceable: usage_threshold,
      invoice_display_name: usage_threshold.threshold_display_name,
      amount_cents: amount_cents,
      amount_currency: invoice.currency,
      fee_type: 'progressive_billing',
      units: 1,
      unit_amount_cents: amount_cents,
      payment_status: 'pending',
      taxes_amount_cents: amount_cents * tax.rate / 100,
      properties: {
        'charges_from_datetime' => invoice_subscription.charges_from_datetime,
        'charges_to_datetime' => invoice_subscription.charges_to_datetime,
        'timestamp' => invoice_subscription.timestamp
      }
    )
  end

  context 'when usage thresold is recurring' do
    let(:usage_threshold) { create(:usage_threshold, :recurring, plan:) }
    let(:amount_cents) { usage_threshold.amount_cents * 5 }

    it 'creates a fee from usage threshold', aggregate_failure: true do
      fee_result = create_service.call

      expect(fee_result).to be_success
      expect(fee_result.fee).to be_present

      fee = fee_result.fee
      expect(fee).to be_persisted
      expect(fee).to have_attributes(
        subscription:,
        invoice:,
        usage_threshold:,
        invoiceable: usage_threshold,
        invoice_display_name: usage_threshold.threshold_display_name,
        amount_cents: amount_cents,
        amount_currency: invoice.currency,
        fee_type: 'progressive_billing',
        units: 5,
        unit_amount_cents: usage_threshold.amount_cents,
        payment_status: 'pending',
        taxes_amount_cents: amount_cents * tax.rate / 100,
        properties: {
          'charges_from_datetime' => invoice_subscription.charges_from_datetime,
          'charges_to_datetime' => invoice_subscription.charges_to_datetime,
          'timestamp' => invoice_subscription.timestamp
        }
      )
    end
  end
end
