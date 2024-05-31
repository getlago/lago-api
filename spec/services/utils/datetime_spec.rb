# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Utils::Datetime, type: :service do
  subject(:datetime) { described_class }

  describe '.valid_format?' do
    it 'returns false for invalid format' do
      expect(datetime).not_to be_valid_format('aaa')
    end

    context 'when parameter is string and is valid' do
      it 'returns true' do
        expect(datetime).to be_valid_format('2022-12-13T12:00:00Z')
      end
    end

    context 'when parameter is datetime object' do
      it 'returns true' do
        expect(datetime).to be_valid_format(Time.current)
      end
    end

    context 'when parameter is a string with microseconds' do
      it 'returns true' do
        expect(datetime).to be_valid_format('2024-05-30T09:45:44.394316274Z')
      end
    end
  end

  describe '.date_diff_with_timezone' do
    let(:from_datetime) { Time.zone.parse('2023-08-31T23:10:00') }
    let(:to_datetime) { Time.zone.parse('2023-09-30T22:59:59') }
    let(:timezone) { 'Europe/Paris' }

    let(:result) do
      datetime.date_diff_with_timezone(
        from_datetime,
        to_datetime,
        timezone
      )
    end

    it 'returns the number of days between the two datetime' do
      expect(result).to eq(30)
    end

    context 'with positive daylight saving time' do
      let(:from_datetime) { Time.zone.parse('2023-09-30T23:10:00') }
      let(:to_datetime) { Time.zone.parse('2023-10-31T22:59:59') }
      let(:timezone) { 'Europe/Paris' }

      it 'takes the daylight saving time into account' do
        expect(result).to eq(31)
      end
    end

    context 'with negative daylight saving time' do
      let(:from_datetime) { Time.zone.parse('2023-02-28T23:10:00') }
      let(:to_datetime) { Time.zone.parse('2023-03-31T21:59:59') }
      let(:timezone) { 'Europe/Paris' }

      it 'takes the daylight saving time into account' do
        expect(result).to eq(31)
      end
    end

    context 'with to date is the beginning of the day' do
      let(:from_datetime) { Time.zone.parse('2023-12-01T00:00:00') }
      let(:to_datetime) { Time.zone.parse('2023-12-07T00:00:00') }
      let(:timezone) { 'UTC' }

      it 'ensures it counts the full days' do
        expect(result).to eq(7)
      end
    end
  end
end
