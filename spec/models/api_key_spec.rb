# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiKey, type: :model do
  it { is_expected.to belong_to(:organization) }

  describe 'validations' do
    describe 'of value uniqueness' do
      before { create(:api_key) }

      it { is_expected.to validate_uniqueness_of(:value) }
    end

    describe 'of value presence' do
      subject { api_key }

      context 'with a new record' do
        let(:api_key) { build(:api_key) }

        it { is_expected.not_to validate_presence_of(:value) }
      end

      context 'with a persisted record' do
        let(:api_key) { create(:api_key) }

        it { is_expected.to validate_presence_of(:value) }
      end
    end
  end

  describe '#save' do
    subject { api_key.save! }

    context 'with a new record' do
      let(:api_key) { build(:api_key) }
      let(:used_value) { create(:api_key).value }
      let(:unique_value) { SecureRandom.uuid }

      before do
        allow(SecureRandom).to receive(:uuid).and_return(used_value, unique_value)
      end

      it 'sets the value' do
        expect { subject }.to change(api_key, :value).to unique_value
      end
    end

    context 'with a persisted record' do
      let(:api_key) { create(:api_key) }

      it 'does not change the value' do
        expect { subject }.not_to change(api_key, :value)
      end
    end
  end
end
