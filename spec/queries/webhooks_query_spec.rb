# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhooksQuery, type: :query do
  subject(:result) do
    described_class.call(webhook_endpoint:, pagination:, search_term:, filters:)
  end

  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { {} }

  let(:organization) { webhook_endpoint.organization.reload }
  let(:webhook_endpoint) { create(:webhook_endpoint) }
  let(:webhook_succeeded) { create(:webhook, :succeeded, webhook_endpoint:) }
  let(:webhook_failed) { create(:webhook, :failed, webhook_endpoint:) }
  let(:webhook_other_type) { create(:webhook, :succeeded, webhook_endpoint:, webhook_type: 'invoice.generated') }

  before do
    webhook_succeeded
    webhook_failed
    webhook_other_type
  end

  it 'returns all webhooks' do
    returned_ids = result.webhooks.pluck(:id)

    aggregate_failures do
      expect(returned_ids.count).to eq(3)
      expect(returned_ids).to include(webhook_succeeded.id)
      expect(returned_ids).to include(webhook_failed.id)
      expect(returned_ids).to include(webhook_other_type.id)
    end
  end

  context 'with pagination' do
    let(:pagination) { {page: 2, limit: 2} }

    it 'applies the pagination' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.webhooks.count).to eq(1)
        expect(result.webhooks.current_page).to eq(2)
        expect(result.webhooks.prev_page).to eq(1)
        expect(result.webhooks.next_page).to be_nil
        expect(result.webhooks.total_pages).to eq(2)
        expect(result.webhooks.total_count).to eq(3)
      end
    end
  end

  context 'when search for /generated/ term' do
    let(:search_term) { 'generated' }

    it 'returns only one webhook' do
      returned_ids = result.webhooks.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).to include(webhook_other_type.id)
      end
    end
  end

  context 'when search for /created/ term and filtering by status' do
    let(:search_term) { 'created' }
    let(:filters) { {status: 'succeeded'} }

    it 'returns only one webhook' do
      returned_ids = result.webhooks.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).to include(webhook_succeeded.id)
      end
    end
  end
end
