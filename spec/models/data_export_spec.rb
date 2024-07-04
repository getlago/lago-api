require 'rails_helper'

RSpec.describe DataExport, type: :model do
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:membership) }

  it { is_expected.to validate_presence_of(:format) }
  it { is_expected.to validate_presence_of(:resource_type) }
  it { is_expected.to validate_presence_of(:resource_query) }
  it { is_expected.to validate_presence_of(:status) }

  describe '#processing!' do
    subject(:processing!) { data_export.processing! }

    let(:data_export) { create :data_export }

    it 'updates status and started_at timestamp' do
      freeze_time do
        expect { processing! }
          .to change(data_export, :status).to('processing')
          .and change(data_export, :started_at).to(Time.zone.now)
      end
    end
  end

  describe '#completed!' do
    subject(:completed!) { data_export.completed! }

    let(:data_export) { create :data_export }

    it 'updates status and started_at timestamp' do
      freeze_time do
        expect { completed! }
          .to change(data_export, :status).to('completed')
          .and change(data_export, :completed_at).to(Time.zone.now)
          .and change(data_export, :expires_at).to(7.days.from_now)
      end
    end
  end

  describe '#expired?' do
    subject(:expired?) { data_export.expired? }

    let(:data_export) { build :data_export }

    it { is_expected.to eq false }

    context 'when export is completed' do
      let(:data_export) { build :data_export, :completed }

      it { is_expected.to eq false }
    end

    context 'when the expiration date is reached' do
      let(:data_export) { build :data_export, :expired }

      it { is_expected.to eq true }
    end
  end

  describe '.filename' do
    subject(:filename) { data_export.filename }

    let(:data_export) { create :data_export, :completed }

    it 'returns the file name' do
      freeze_time do
        timestamp = Time.zone.now.strftime('%Y%m%d%H%M%S')
        expect(filename).to eq("#{timestamp}_invoices.csv")
      end
    end

    context 'when data export does not have a file' do
      let(:data_export) { create :data_export }

      it { is_expected.to be_nil }
    end
  end

  describe '.file_url' do
    subject(:file_url) { data_export.file_url }

    let(:data_export) { create :data_export, :completed }

    it 'returns the file url' do
      expect(file_url).to be_present
      expect(file_url).to include(ENV['LAGO_API_URL'])
    end

    context 'when data export does not have a file' do
      let(:data_export) { create :data_export }

      it { is_expected.to be_nil }
    end
  end
end
