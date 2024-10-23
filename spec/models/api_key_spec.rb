# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiKey, type: :model do
  it { is_expected.to belong_to(:organization) }

  describe '#save' do
    subject { api_key.save! }

    before do
      allow(api_key).to receive(:set_value).and_call_original
      subject
    end

    context 'with a new record' do
      let(:api_key) { build(:api_key) }

      it 'calls #set_value' do
        expect(api_key).to have_received(:set_value)
      end
    end

    context 'with a persisted record' do
      let(:api_key) { create(:api_key) }

      it 'does not call #set_value' do
        expect(api_key).not_to have_received(:set_value)
      end
    end
  end

  describe '#set_value' do
    subject { api_key.send(:set_value) }

    let(:api_key) { build(:api_key) }
    let(:unique_value) { SecureRandom.uuid }

    before { allow(api_key).to receive(:generate_value).and_return(unique_value) }

    it 'sets result of #generate_value to the value' do
      expect { subject }.to change(api_key, :value).to unique_value
    end
  end

  describe '#generate_value' do
    subject { api_key.generate_value }

    let(:api_key) { build(:api_key) }
    let(:used_value) { create(:api_key).value }
    let(:unique_value) { SecureRandom.uuid }

    before do
      allow(SecureRandom).to receive(:uuid).and_return(used_value, unique_value)
    end

    it 'returns unique value between all ApiKeys' do
      expect(subject).to eq unique_value
    end
  end
end
