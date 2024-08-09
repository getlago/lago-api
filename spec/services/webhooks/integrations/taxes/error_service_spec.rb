# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::Integrations::Taxes::ErrorService do
  subject(:webhook_service) { described_class.new(object: integration, options: webhook_options) }

  let(:integration) { create(:anrok_integration, organization:) }
  let(:organization) { create(:organization) }
  let(:webhook_options) do
    {
      provider_error: {message: 'message', error_code: 'code'}
    }
  end

  describe '.call' do
    it_behaves_like 'creates webhook', 'integration.tax_provider_error', 'tax_provider_error'
  end
end
