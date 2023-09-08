# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Utils::DatetimeService, type: :service do
  subject(:datetime_service) { described_class }

  describe '.valid_format?' do
    it 'returns false for invalid format' do
      expect(datetime_service.valid_format?('aaa')).to be_falsey
    end

    context 'when parameter is string and is valid' do
      it 'returns true' do
        expect(datetime_service.valid_format?('2022-12-13T12:00:00Z')).to be_truthy
      end
    end

    context 'when parameter is datetime object' do
      it 'returns true' do
        expect(datetime_service.valid_format?(Time.current)).to be_truthy
      end
    end
  end
end
