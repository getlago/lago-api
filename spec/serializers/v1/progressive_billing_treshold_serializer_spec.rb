# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::ProgressiveBillingTresholdSerializer do
  subject(:serializer) { described_class.new(progressive_billing_treshold, root_name: 'progressive_billing_treshold') }

  let(:progressive_billing_treshold) { create(:progressive_billing_treshold) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['progressive_billing_treshold']).to include(
        'lago_id' => progressive_billing_treshold.id,
        'treshold_display_name' => progressive_billing_treshold.treshold_display_name,
        'amount_cents' => progressive_billing_treshold.amount_cents,
        'amount_currency' => progressive_billing_treshold.amount_currency,
        'recurring' => progressive_billing_treshold.recurring?,
        'created_at' => progressive_billing_treshold.created_at.iso8601,
        'updated_at' => progressive_billing_treshold.updated_at.iso8601
      )
    end
  end
end
