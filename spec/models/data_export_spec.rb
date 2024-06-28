require 'rails_helper'

RSpec.describe DataExport, type: :model do
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:membership) }

  it { is_expected.to validate_presence_of(:format) }
  it { is_expected.to validate_presence_of(:resource_type) }
  it { is_expected.to validate_presence_of(:resource_query) }
  it { is_expected.to validate_presence_of(:status) }

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
end
