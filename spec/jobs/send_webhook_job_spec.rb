# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendWebhookJob, type: :job do
  let(:webhook_invoice_service) { instance_double(Webhooks::InvoicesService) }
  let(:organization) { create(:organization, webhook_url: 'http://foo.bar') }
  let(:invoice) { create(:invoice) }

  it 'calls the webhook invoice service' do
    allow(Webhooks::InvoicesService).to receive(:new)
      .with(invoice)
      .and_return(webhook_invoice_service)
    allow(webhook_invoice_service).to receive(:call)

    described_class.perform_now(:invoice, invoice)

    expect(Webhooks::InvoicesService).to have_received(:new)
    expect(webhook_invoice_service).to have_received(:call)
  end

  context 'with not implemented webhook type' do
    it 'raises a NotImplementedError' do
      expect { described_class.perform_now(:subscription, invoice) }
        .to raise_error(NotImplementedError)
    end
  end
end
