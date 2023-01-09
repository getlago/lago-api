# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::GenerateService, type: :service do
  subject(:credit_note_generate_service) { described_class.new }

  let(:organization) { create(:organization, name: 'LAGO') }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:) }
  let(:credit_note) { create(:credit_note, invoice:, customer:) }
  let(:fee) { create(:fee, invoice:) }
  let(:credit_note_item) { create(:credit_note_item, credit_note:, fee:) }
  let(:pdf_generator) { instance_double(Utils::PdfGenerator) }

  let(:pdf_content) do
    File.read(Rails.root.join('spec/fixtures/blank.pdf'))
  end

  let(:pdf_response) do
    BaseService::Result.new.tap { |r| r.io = StringIO.new(pdf_content) }
  end

  before do
    credit_note_item

    allow(Utils::PdfGenerator).to receive(:new)
      .and_return(pdf_generator)
    allow(pdf_generator).to receive(:call)
      .and_return(pdf_response)
  end

  describe '.call' do
    it 'generates the credit note synchronously' do
      result = credit_note_generate_service.call(credit_note_id: credit_note.id)

      expect(result.credit_note.file).to be_present
    end

    context 'with not found credit_note' do
      it 'returns a result with error' do
        result = credit_note_generate_service.call(credit_note_id: '123456')

        expect(result.success).to be_falsey
        expect(result.error.error_code).to eq('credit_note_not_found')
      end
    end

    context 'when credit_note is draft' do
      let(:credit_note) { create(:credit_note, :draft, invoice:, customer:) }

      it 'returns a not found error' do
        result = credit_note_generate_service.call(credit_note_id: credit_note.id)

        expect(result.success).to be_falsey
        expect(result.error.error_code).to eq('credit_note_not_found')
      end
    end

    context 'with already generated file' do
      before do
        credit_note.file.attach(
          io: StringIO.new(File.read(Rails.root.join('spec/fixtures/blank.pdf'))),
          filename: 'credit_note.pdf',
          content_type: 'application/pdf',
        )
      end

      it 'does not generate the pdf' do
        allow(LagoHttpClient::Client).to receive(:new)

        credit_note_generate_service.call(credit_note_id: credit_note.id)

        expect(LagoHttpClient::Client).not_to have_received(:new)
      end
    end
  end

  describe '.call_from_api' do
    it 'generates the credit_note' do
      credit_note_generate_service.call_from_api(credit_note:)

      expect(credit_note.file).to be_present
    end

    it 'calls the SendWebhook job' do
      expect do
        credit_note_generate_service.call_from_api(credit_note:)
      end.to have_enqueued_job(SendWebhookJob)
    end
  end
end
