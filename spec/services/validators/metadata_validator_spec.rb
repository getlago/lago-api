# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Validators::MetadataValidator, type: :validator do
  subject(:metadata_validator) { described_class.new(metadata) }

  let(:max_keys) { Validators::MetadataValidator::DEFAULT_CONFIG[:max_keys] }
  let(:max_key_length) { Validators::MetadataValidator::DEFAULT_CONFIG[:max_key_length] }
  let(:max_value_length) { Validators::MetadataValidator::DEFAULT_CONFIG[:max_value_length] }

  describe '.valid?' do
    let(:metadata) { {key1: 'valid_value', key2: 'also_valid'} }

    it 'returns true for valid metadata' do
      expect(metadata_validator).to be_valid
    end

    context 'when metadata has too many keys' do
      let(:metadata) { (1..max_keys + 1).map { |i| %W[key#{i} value#{i}] }.to_h }

      it 'returns false' do
        expect(metadata_validator).not_to be_valid
        expect(metadata_validator.errors[:metadata]).to include('too_many_keys')
      end
    end

    context 'when metadata contains a key that is too long' do
      let(:metadata) { {'a' * (max_key_length + 1) => 'valid'} }

      it 'returns false' do
        expect(metadata_validator).not_to be_valid
        expect(metadata_validator.errors[:metadata]).to include('key_too_long')
      end
    end

    context 'when metadata contains a value that is too long' do
      let(:metadata) { {'key' => 'a' * (max_value_length + 1)} }

      it 'returns false' do
        expect(metadata_validator).not_to be_valid
        expect(metadata_validator.errors[:metadata]).to include('value_too_long')
      end
    end

    context 'when metadata contains nested structures' do
      let(:metadata) { {'key' => {'nested_key' => 'value'}} }

      it 'returns false' do
        expect(metadata_validator).not_to be_valid
        expect(metadata_validator.errors[:metadata]).to include('nested_structure_not_allowed')
      end
    end

    context 'when metadata is empty' do
      let(:metadata) { {} }

      it 'returns true' do
        expect(metadata_validator).to be_valid
      end
    end
  end
end
