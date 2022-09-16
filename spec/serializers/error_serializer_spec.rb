# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ErrorSerializer do
  let(:transaction_id) { SecureRandom.uuid }
  let(:object) do
    {
      input_params: {
        customer_id: 'customer',
        transaction_id: transaction_id,
        code: 'code',
      },
      error: 'Event not found',
      status: 404,
      organization_id: 'testtest',
    }
  end
  let(:json_response_hash) do
    {
      'event_error' => {
        'status' => 404,
        'error' => 'Not found',
        'message' => 'Event not found',
        'input_params' => {
          'customer_id' => 'customer',
          'transaction_id' => transaction_id,
          'code' => 'code',
        }
      }
    }
  end
  let(:serializer) do
    described_class.new(OpenStruct.new(object), root_name: 'event_error')
  end
  let(:result) { JSON.parse(serializer.to_json) }

  it 'serializes object' do
    expect(result).to eq json_response_hash
  end
end
