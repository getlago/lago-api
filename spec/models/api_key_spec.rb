# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiKey, type: :model do
  it { is_expected.to belong_to(:organization) }

  it { is_expected.to validate_presence_of(:permissions) }

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

    describe 'of permissions structure' do
      subject { api_key.valid? }

      let(:api_key) { build_stubbed(:api_key) }
      let(:missing_error) { api_key.errors.where(:permissions, :missing_keys) }
      let(:forbidden_error) { api_key.errors.where(:permissions, :forbidden_keys) }

      context 'when permissions has forbidden keys' do
        before { api_key.permissions = api_key.permissions.merge(forbidden: []) }

        context 'when permissions has required keys missing' do
          before do
            api_key.permissions.delete('add_on')
            subject
          end

          it 'adds forbidden keys error' do
            expect(forbidden_error).to be_present
          end

          it 'adds missing keys error' do
            expect(missing_error).to be_present
          end
        end

        context 'when permissions all required keys present' do
          before { subject }

          it 'adds forbidden keys error' do
            expect(forbidden_error).to be_present
          end

          it 'does not add missing keys error' do
            expect(missing_error).not_to be_present
          end
        end
      end

      context 'when permissions has no forbidden keys' do
        context 'when permissions has required keys missing' do
          before do
            api_key.permissions.delete('add_on')
            subject
          end

          it 'does not add forbidden keys error' do
            expect(forbidden_error).not_to be_present
          end

          it 'adds missing keys error' do
            expect(missing_error).to be_present
          end
        end

        context 'when permissions all required keys present' do
          before { subject }

          it 'does not add forbidden keys error' do
            expect(forbidden_error).not_to be_present
          end

          it 'does not add missing keys error' do
            expect(missing_error).not_to be_present
          end
        end
      end
    end

    describe 'of permissions values' do
      subject { api_key.valid? }

      let(:api_key) { build_stubbed(:api_key, permissions:) }
      let(:error) { api_key.errors.where(:permissions, :forbidden_values) }

      before { subject }

      context 'when permission contains forbidden values' do
        let(:permissions) { {add_on: ['forbidden', 'read']} }

        it 'adds an error' do
          expect(error).to be_present
        end
      end

      context 'when permission contains only allowed values' do
        let(:permissions) { {add_on: ['read', 'write']} }

        it 'does not add an error' do
          expect(error).not_to be_present
        end
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

  describe 'default_scope' do
    subject { described_class.all }

    let!(:scoped) do
      [
        create(:api_key),
        create(:api_key, :expiring)
      ]
    end

    before { create(:api_key, :expired) }

    it 'returns API keys with either no expiration or future expiration dates' do
      expect(subject).to match_array scoped
    end
  end

  describe '.non_expiring' do
    subject { described_class.non_expiring }

    let!(:scoped) { create(:api_key) }

    before { create(:api_key, :expiring) }

    it 'returns API keys with no expiration date' do
      expect(subject).to contain_exactly scoped
    end
  end

  describe "#permit?" do
    subject { api_key.permit?(resource, mode) }

    let(:api_key) { create(:api_key) }
    let(:resource) { described_class::RESOURCES.sample }
    let(:mode) { described_class::MODES.sample }

    before { api_key.organization.update!(premium_integrations:) }

    context "when organization has 'api_permissions' add-on enabled" do
      let(:premium_integrations) { ["api_permissions"] }

      context "when corresponding resource allows provided mode" do
        it "returns true" do
          expect(subject).to be true
        end
      end

      context "when corresponding resource does not allow provided mode" do
        before do
          api_key.permissions = api_key.permissions.merge(resource => described_class::MODES.excluding(mode))
        end

        it "returns false" do
          expect(subject).to be false
        end
      end
    end

    context "when organization has 'api_permissions' add-on disabled" do
      let(:premium_integrations) { [] }

      context "when corresponding resource allows provided mode" do
        it "returns true" do
          expect(subject).to be true
        end
      end

      context "when corresponding resource does not allow provided mode" do
        before do
          api_key.permissions = api_key.permissions.merge(resource => described_class::MODES.excluding(mode))
        end

        it "returns true" do
          expect(subject).to be true
        end
      end
    end
  end
end
