# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::GenerateService, type: :service do
  subject(:invoice_generate_service) { described_class.new }

  let(:organization) { create(:organization, name: 'LAGO') }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, organization: organization, customer: customer) }
  let(:invoice) { create(:invoice, customer: customer) }
  let(:credit) { create(:credit, invoice: invoice) }
  let(:fees) { create_list(:fee, 3, invoice: invoice) }
  let(:invoice_subscription) { create(:invoice_subscription, invoice: invoice, subscription: subscription) }
  let(:pdf_content) do
    File.read(Rails.root.join('spec/fixtures/blank.pdf'))
  end

  let(:pdf_generator) { instance_double(Utils::PdfGenerator) }
  let(:pdf_response) do
    BaseService::Result.new.tap { |r| r.io = StringIO.new(pdf_content) }
  end

  before do
    invoice_subscription

    allow(Utils::PdfGenerator).to receive(:new)
      .and_return(pdf_generator)
    allow(pdf_generator).to receive(:call)
      .and_return(pdf_response)
  end

  describe '.generate' do
    it 'generates the invoice synchronously' do
      result = invoice_generate_service.generate(invoice_id: invoice.id)

      expect(result.invoice.file).to be_present
    end

    context 'with not found invoice' do
      it 'returns a result with error' do
        result = invoice_generate_service.generate(invoice_id: '123456')

        expect(result.success).to be_falsey
        expect(result.error.error_code).to eq('invoice_not_found')
      end
    end

    context 'with already generated file' do
      before do
        invoice.file.attach(
          io: StringIO.new(File.read(Rails.root.join('spec/fixtures/blank.pdf'))),
          filename: 'invoice.pdf',
          content_type: 'application/pdf',
        )
      end

      it 'does not generate the pdf' do
        allow(LagoHttpClient::Client).to receive(:new)

        invoice_generate_service.generate(invoice_id: invoice.id)

        expect(LagoHttpClient::Client).not_to have_received(:new)
      end
    end
  end

  describe '.generate_from_api' do
    it 'generates the invoice' do
      invoice_generate_service.generate_from_api(invoice)

      expect(invoice.file).to be_present
    end

    it 'calls the SendWebhook job' do
      expect do
        invoice_generate_service.generate_from_api(invoice)
      end.to have_enqueued_job(SendWebhookJob)
    end
  end
end
