# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Metadata::CustomerMetadata, type: :model do
  subject(:metadata) { described_class.new(attributes) }

  let(:customer) { create(:customer) }
  let(:key) { 'hello' }
  let(:value) { 'abcdef' }
  let(:attributes) do
    { key:, value:, customer:, display_in_invoice: true }
  end

  describe 'key validations' do
    context 'when uniqueness condition is satisfied', :tag do
      it { expect(metadata).to be_valid }
    end

    context 'when key is not unique' do
      let(:old_metadata) { create(:customer_metadata, customer:, key: 'hello') }

      before { old_metadata }

      it { expect(metadata).not_to be_valid }
    end

    context 'when key length is invalid' do
      let(:key) { 'hello-hello-hello-hello-hello' }

      it { expect(metadata).not_to be_valid }
    end
  end

  describe 'value validations' do
    context 'when length constraint is satisfied', :tag do
      it { expect(metadata).to be_valid }
    end

    context 'when value length is invalid' do
      let(:value) { 'abcde-abcde-abcde-abcde-abcde-abcde' }

      it { expect(metadata).to be_valid }
    end
  end
end
