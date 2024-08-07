# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::UsageTresholdSerializer do
  subject(:serializer) { described_class.new(usage_treshold, root_name: 'usage_treshold') }

  let(:usage_treshold) { create(:usage_treshold) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['usage_treshold']).to include(
        'lago_id' => usage_treshold.id,
        'treshold_display_name' => usage_treshold.treshold_display_name,
        'amount_cents' => usage_treshold.amount_cents,
        'amount_currency' => usage_treshold.amount_currency,
        'recurring' => usage_treshold.recurring?,
        'created_at' => usage_treshold.created_at.iso8601,
        'updated_at' => usage_treshold.updated_at.iso8601
      )
    end
  end
end
