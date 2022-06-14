# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendWebhookJob, type: :job do
  let(:webhook_invoice_service) { instance_double(Webhooks::InvoicesService) }
  let(:webhook_add_on_service) { instance_double(Webhooks::AddOnService) }
  let(:webhook_event_service) { instance_double(Webhooks::EventService) }
  let(:organization) { create(:organization, webhook_url: 'http://foo.bar') }
  let(:invoice) { create(:invoice) }

  context 'when webhook_type is invoice' do
    before do
      allow(Webhooks::InvoicesService).to receive(:new)
        .with(invoice)
        .and_return(webhook_invoice_service)
      allow(webhook_invoice_service).to receive(:call)
    end

    it 'calls the webhook invoice service' do
      described_class.perform_now(:invoice, invoice)

      expect(Webhooks::InvoicesService).to have_received(:new)
      expect(webhook_invoice_service).to have_received(:call)
    end
  end

  context 'when webhook_type is add_on' do
    before do
      allow(Webhooks::AddOnService).to receive(:new)
        .with(invoice)
        .and_return(webhook_add_on_service)
      allow(webhook_add_on_service).to receive(:call)
    end

    it 'calls the webhook invoice service' do
      described_class.perform_now(:add_on, invoice)

      expect(Webhooks::AddOnService).to have_received(:new)
      expect(webhook_add_on_service).to have_received(:call)
    end
  end

  context 'when webhook_type is event' do
    let(:object) do
      {
        input_params: {
          customer_id: 'customer',
          transaction_id: SecureRandom.uuid,
          code: 'code'
        },
        error: 'Code does not exist',
        organization_id: organization.id
      }
    end

    before do
      allow(Webhooks::EventService).to receive(:new)
        .with(object)
        .and_return(webhook_event_service)
      allow(webhook_event_service).to receive(:call)
    end

    it 'calls the webhook event service' do
      described_class.perform_now(:event, object)

      expect(Webhooks::EventService).to have_received(:new)
      expect(webhook_event_service).to have_received(:call)
    end
  end

  context 'with not implemented webhook type' do
    it 'raises a NotImplementedError' do
      expect { described_class.perform_now(:subscription, invoice) }
        .to raise_error(NotImplementedError)
    end
  end
end
