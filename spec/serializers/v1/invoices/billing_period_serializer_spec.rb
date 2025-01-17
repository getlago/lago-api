# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::Invoices::BillingPeriodSerializer do
  subject(:serializer) { described_class.new(invoice_subscription, root_name: 'billing_period') }

  let(:invoice_subscription) { build(:invoice_subscription, :boundaries) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['billing_period']['lago_subscription_id']).to eq(invoice_subscription.subscription_id)
      expect(result['billing_period']['external_subscription_id']).to eq(invoice_subscription.subscription.external_id)
      expect(result['billing_period']['lago_plan_id']).to eq(invoice_subscription.subscription.plan_id)
      expect(result['billing_period']['subscription_from_datetime']).to eq(invoice_subscription.from_datetime.iso8601)
      expect(result['billing_period']['subscription_to_datetime']).to eq(invoice_subscription.to_datetime.iso8601)
      expect(result['billing_period']['charges_from_datetime']).to eq(invoice_subscription.charges_from_datetime.iso8601)
      expect(result['billing_period']['charges_to_datetime']).to eq(invoice_subscription.charges_to_datetime.iso8601)
      expect(result['billing_period']['invoicing_reason']).to eq(invoice_subscription.invoicing_reason)
    end
  end
end
