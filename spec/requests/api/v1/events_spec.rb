# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::EventsController, type: :request do
  let(:organization) { create(:organization) }

  describe 'POST /events' do
    it 'returns a success' do
      post_with_token(
        organization,
        '/api/v1/events',
        event: {
          code: 'event_code',
          transaction_id: SecureRandom.uuid,
          customer_id: SecureRandom.uuid,
          timestamp: Time.zone.now.to_i,
          properties: {
            foo: 'bar',
          },
        },
      )

      expect(response).to have_http_status(:ok)
      expect(CreateEventJob).to have_been_enqueued
    end
  end
end
