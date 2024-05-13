# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::InvoicedUsage, type: :model do
  describe '.cache_key' do
    subject(:invoiced_usage_cache_key) { described_class.cache_key(organization_id, **args) }

    let(:organization_id) { SecureRandom.uuid }
    let(:currency) { 'EUR' }
    let(:months) { 12 }
    let(:date) { Date.current.strftime('%Y-%m-%d') }

    context 'with no arguments' do
      let(:args) { {} }
      let(:cache_key) { "invoiced-usage/#{date}/#{organization_id}//" }

      it 'returns the cache key' do
        expect(invoiced_usage_cache_key).to eq(cache_key)
      end
    end

    context 'with currency and months' do
      let(:args) { {currency:, months:} }

      let(:cache_key) do
        "invoiced-usage/#{date}/#{organization_id}/#{currency}/#{months}"
      end

      it 'returns the cache key' do
        expect(invoiced_usage_cache_key).to eq(cache_key)
      end
    end

    context 'with months' do
      let(:args) { {months:} }

      let(:cache_key) do
        "invoiced-usage/#{date}/#{organization_id}//#{months}"
      end

      it 'returns the cache key' do
        expect(invoiced_usage_cache_key).to eq(cache_key)
      end
    end

    context 'with currency' do
      let(:args) { {currency:} }
      let(:cache_key) { "invoiced-usage/#{date}/#{organization_id}/#{currency}/" }

      it 'returns the cache key' do
        expect(invoiced_usage_cache_key).to eq(cache_key)
      end
    end
  end
end
