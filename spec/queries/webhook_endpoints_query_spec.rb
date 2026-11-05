# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpointsQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, search_term:)
  end

  let(:returned_ids) { result.webhook_endpoints.pluck(:id) }

  let(:pagination) { nil }
  let(:search_term) { nil }

  let(:organization) { create :organization }
  let(:webhook_endpoint_first) { create(:webhook_endpoint, organization:, webhook_url: "https://www.getlago.com/webhooks") }
  let(:webhook_endpoint_second) { create(:webhook_endpoint, organization:, webhook_url: "https://test.com/lago-webhooks") }
  let(:webhook_endpoint_third) { create(:webhook_endpoint, organization:, webhook_url: "https://www.google.com/v1/hooks") }
  let(:webhook_endpoint_fourth) { create(:webhook_endpoint, organization: create(:organization), webhook_url: "https://www.getlago.com/webhooks") }

  before do
    organization.webhook_endpoints.destroy_all # organization factory creates a webhook endpoint
    webhook_endpoint_first
    webhook_endpoint_second
    webhook_endpoint_third
    webhook_endpoint_fourth
  end

  it "returns all webhook endpoints of the organization" do
    expect(result.webhook_endpoints.count).to eq(3)
    expect(returned_ids).to include(webhook_endpoint_first.id)
    expect(returned_ids).to include(webhook_endpoint_second.id)
    expect(returned_ids).to include(webhook_endpoint_third.id)
    expect(returned_ids).not_to include(webhook_endpoint_fourth.id)
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 2} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.webhook_endpoints.count).to eq(1)
      expect(result.webhook_endpoints.current_page).to eq(2)
      expect(result.webhook_endpoints.prev_page).to eq(1)
      expect(result.webhook_endpoints.next_page).to be_nil
      expect(result.webhook_endpoints.total_pages).to eq(2)
      expect(result.webhook_endpoints.total_count).to eq(3)
    end
  end

  context "with a created_at range" do
    subject(:result) do
      described_class.call(organization:, filters: {created_at_from: "2026-10-01", created_at_to: "2026-10-31"})
    end

    before do
      webhook_endpoint_first.update!(created_at: Time.zone.parse("2026-09-30T23:59:59Z"))
      webhook_endpoint_second.update!(created_at: Time.zone.parse("2026-10-31T23:59:59Z"))
      webhook_endpoint_third.update!(created_at: Time.zone.parse("2026-11-01T00:00:00Z"))
    end

    it "returns the endpoints created in the range, its last day included" do
      expect(returned_ids).to eq([webhook_endpoint_second.id])
    end
  end

  context "with an invalid created_at bound" do
    subject(:result) { described_class.call(organization:, filters: {created_at_from: "2026-13-01"}) }

    it "fails with invalid_date" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(created_at_from: ["invalid_date"])
    end
  end

  context "when searching for /lago/ term" do
    let(:search_term) { "lago" }

    it "returns only two webhook_endpoints" do
      expect(result.webhook_endpoints.count).to eq(2)
      expect(returned_ids).to include(webhook_endpoint_first.id)
      expect(returned_ids).to include(webhook_endpoint_second.id)
      expect(returned_ids).not_to include(webhook_endpoint_third.id)
      expect(returned_ids).not_to include(webhook_endpoint_fourth.id)
    end
  end
end
