# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::EventErrorSerializer do
  subject(:serializer) { described_class.new(event_error, root_name: 'event_error') }

  let(:event_error) do
    OpenStruct.new(
      error: { transaction_id: ['value_already_exist'] },
      event: create(:received_event),
    )
  end

  let(:result) { JSON.parse(serializer.to_json) }

  it 'serializes object' do
    aggregate_failures do
      expect(result['event_error']).to include(
        'status' => 422,
        'error' => 'Unprocessable entity',
        'message' => '{"transaction_id":["value_already_exist"]}',
      )

      expect(result['event_error']['event']).to include(
        'lago_id' => event_error.event.id,
        'transaction_id' => event_error.event.transaction_id,
        'lago_customer_id' => nil,
        'external_customer_id' => event_error.event.external_customer_id,
        'code' => event_error.event.code,
        'timestamp' => event_error.event.timestamp.iso8601(3),
        'properties' => event_error.event.properties,
        'lago_subscription_id' => nil,
        'external_subscription_id' => event_error.event.external_subscription_id,
        'created_at' => event_error.event.created_at.iso8601,
      )

      # NOTE: legacy values
      expect(result['event_error']['input_params']).to include(
        'transaction_id' => event_error.event.transaction_id,
        'external_subscription_id' => event_error.event.external_subscription_id,
        'external_customer_id' => event_error.event.external_customer_id,
        'timestamp' => event_error.event.timestamp.to_f,
        'code' => event_error.event.code,
        'properties' => event_error.event.properties,
      )
    end
  end
end
