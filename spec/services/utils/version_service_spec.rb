# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Utils::VersionService, type: :service do
  subject(:version_service) { described_class.new }

  describe '.version' do
    context 'with tagged version' do
      let(:version) { 'v0.3.0-alpha' }

      it 'returns current version details' do
        allow(File).to receive(:read)
          .and_return(version)

        result = version_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.version.number).to eq(version)
          expect(result.version.github_url).to eq("https://github.com/getlago/lago-api/tree/#{version}")
        end
      end
    end

    context 'with github hash' do
      let(:version) { '204720b463148d3a44172d17446bd2721d9f7c40' }
      let(:release_date) { Time.zone.now }

      it 'returns current version details' do
        allow(File).to receive(:read)
          .and_return(version)
        allow(File).to receive(:ctime)
          .and_return(release_date)

        result = version_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.version.number).to eq(release_date.to_date.iso8601)
          expect(result.version.github_url).to eq("https://github.com/getlago/lago-api/tree/#{version}")
        end
      end
    end

    context 'without version file' do
      it 'returns current version details' do
        allow(File).to receive(:read)
          .and_raise(Errno::ENOENT)

        result = version_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.version.number).to eq('test')
          expect(result.version.github_url).to eq('https://github.com/getlago/lago-api')
        end
      end
    end
  end
end
