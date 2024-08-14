# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataExportMailer, type: :mailer do
  subject(:data_export_mailer) { described_class }

  let(:data_export) { create(:data_export, :completed) }

  describe '#completed' do
    let(:mailer) { data_export_mailer.with(data_export:).completed }
    let(:file_url) { "https://api.lago.dev/rails/active_storage/blobs/redirect/eyJf" }

    before do
      allow(data_export).to receive(:file_url).and_return(file_url)
    end

    specify do
      expect(mailer.to).to eq([data_export.user.email])
      expect(mailer.subject).to eq("Your Lago invoices export is ready!")
      expect(mailer.body.encoded).to match("Your invoices export is ready!")
      expect(mailer.body.encoded).to match("will be available for 7 days")
      expect(mailer.body.encoded).to match(data_export.file_url)
    end

    context "when the resource type is invoice_fees" do
      let(:data_export) { create(:data_export, :completed, resource_type: 'invoice_fees') }

      specify do
        expect(mailer.subject).to eq("Your Lago invoice fees export is ready!")
        expect(mailer.body.encoded).to match("Your invoice fees export is ready!")
      end
    end

    context 'when data export is expired' do
      let(:data_export) { create(:data_export, :expired) }

      it 'does something' do
        expect(mailer.to).to be_nil
      end
    end

    context 'when data export is not completed' do
      let(:data_export) { create(:data_export, :processing) }

      it 'returns a mailer with nil values' do
        expect(mailer.to).to be_nil
      end
    end

    context 'when data export has no attached file' do
      let(:data_export) { create(:data_export, :completed, file: nil) }

      it 'returns a mailer with nil values' do
        expect(mailer.to).to be_nil
      end
    end
  end
end
