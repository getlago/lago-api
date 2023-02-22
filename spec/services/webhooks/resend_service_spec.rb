# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::ResendService, type: :service do
  subject(:resend_service) { described_class.new(webhook:) }

  let(:webhook) { create(:webhook, :failed) }

  it 'enqueues a SendWebhookJob' do
    expect { resend_service.call }.to have_enqueued_job(SendWebhookJob)
      .with(
        webhook.webhook_type,
        nil,
        {},
        webhook.id,
      )
  end

  context 'when webhook is not found' do
    let(:webhook) { nil }

    it 'returns an error' do
      result = resend_service.call

      expect(result).not_to be_success
      expect(result.error.error_code).to eq('webhook_not_found')
    end
  end

  context 'when webhook is succeeded' do
    let(:webhook) { create(:webhook, :succeeded) }

    it 'returns an error' do
      result = resend_service.call

      expect(result).not_to be_success
      expect(result.error.code).to eq('is_succeeded')
    end
  end
end
