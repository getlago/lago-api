# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::CreditNotes::CreatedService do
  subject(:webhook_service) { described_class.new(credit_note) }

  let(:credit_note) { create(:credit_note, customer: customer) }

  let(:organization) { create(:organization, webhook_url: webhook_url) }
  let(:customer) { create(:customer, organization: organization) }
  let(:webhook_url) { 'http://foo.bar' }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post)
    end

    it 'builds payload with credit_note.created webhook type' do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post) do |payload|
        expect(payload[:webhook_type]).to eq('credit_note.created')
        expect(payload[:object_type]).to eq('credit_note')
        expect(payload['credit_note'][:customer]).to be_present
        expect(payload['credit_note']['items']).to eq([])
      end
    end
  end
end
