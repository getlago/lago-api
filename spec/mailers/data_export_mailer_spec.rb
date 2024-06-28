require 'rails_helper'

RSpec.describe DataExportMailer, type: :mailer do
  subject(:data_export_mailer) { described_class }

  let(:data_export) { create(:data_export, :completed) }

  describe '#completed' do
    let(:mailer) { data_export_mailer.with(data_export:).completed }

    specify do
      expect(mailer.to).to eq([data_export.user.email])
    end

    context 'when data export is expired' do
      let(:data_export) { create(:data_export, :expired) }

      it 'does something' do
        expect(mailer.to).to be_nil
      end
    end

    context 'when data export is not completed' do
      let(:data_export) { create(:data_export, :processing) }

      it 'does something' do
        expect(mailer.to).to be_nil
      end
    end

    context 'when data export has no attached file' do
      let(:data_export) { create(:data_export, :completed, file: nil) }

      it 'does something' do
        expect(mailer.to).to be_nil
      end
    end
  end
end
