# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Metadata::CustomerMetadata, type: :model do
  subject(:metadata) { described_class.new(attributes) }

  let(:customer) { create(:customer) }
  let(:key) { 'hello' }
  let(:value) { 'abcdef' }
  let(:attributes) do
    { key: key, value: value, customer: customer, display_in_invoice: true }
  end

  describe 'validations' do
    context 'when key is unique' do
      it 'validates the key' do
        expect(metadata).to be_valid
      end
    end

    context 'when key is not unique' do
      let(:old_metadata) { create(:customer_metadata, customer: customer, key: 'hello') }

      before { old_metadata }

      it 'validates the key' do
        expect(metadata).not_to be_valid
      end
    end

    context 'when key length is valid' do
      it 'validates the key' do
        expect(metadata).to be_valid
      end
    end

    context 'when key length is not valid' do
      let(:key) { 'hello-hello-hello-hello-hello' }

      it 'validates the key' do
        expect(metadata).not_to be_valid
      end
    end

    context 'when value length is valid' do
      it 'validates the key' do
        expect(metadata).to be_valid
      end
    end

    context 'when value length is not valid' do
      let(:value) { 'abcde-abcde-abcde-abcde-abcde-abcde' }

      it 'validates the key' do
        expect(metadata).to be_valid
      end
    end
  end
end
