# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiLogsQuery, type: :query, clickhouse: true do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:)
  end

  let(:returned_ids) { result.api_logs.pluck(:request_id) }
  let(:organization) { api_log.organization }
  let(:api_log) { create(:clickhouse_api_log) }
  let(:pagination) { {page: 1, limit: 10} }
  let(:filters) { nil }

  before do
    api_log
  end

  it "returns all api logs" do
    expect(result.api_logs.count).to eq(1)
    expect(returned_ids).to include(api_log.request_id)
  end

  context "with old api logs" do
    let(:old_api_log) do
      create(
        :clickhouse_api_log,
        organization:,
        logged_at: (ApiLogsQuery::MAX_AGE + 3.days).ago
      )
    end

    before do
      old_api_log
    end

    it "returns only recent ones" do
      expect(result.api_logs.count).to eq(1)
      expect(returned_ids).to eq([api_log.request_id])
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 1, limit: 1} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.api_logs.count).to eq(1)
      expect(result.api_logs.current_page).to eq(1)
      expect(result.api_logs.prev_page).to be_nil
      expect(result.api_logs.next_page).to be_nil
      expect(result.api_logs.total_pages).to eq(1)
      expect(result.api_logs.total_count).to eq(1)
    end
  end

  context "with from_date and to_date filters" do
    it "returns expected api logs" do
      filters = {from_date: api_log.logged_at + 1.day}
      expect(described_class.call(organization:, pagination:, filters:).api_logs).to be_empty

      filters = {from_date: api_log.logged_at - 1.day, to_date: api_log.logged_at + 1.day}
      expect(described_class.call(organization:, pagination:, filters:).api_logs.first.request_id).to eq(api_log.request_id)

      filters = {to_date: api_log.logged_at - 1.day}
      expect(described_class.call(organization:, pagination:, filters:).api_logs).to be_empty
    end
  end

  context "with api_key_ids filter" do
    it "returns expected api logs" do
      filters = {api_key_ids: [api_log.api_key_id]}
      expect(described_class.call(organization:, pagination:, filters:).api_logs.first.request_id).to eq(api_log.request_id)

      filters = {api_key_ids: ["other"]}
      expect(described_class.call(organization:, pagination:, filters:).api_logs).to be_empty
    end
  end

  context "with http_methods filter" do
    it "returns expected api logs" do
      filters = {http_methods: [api_log.http_method]}
      expect(described_class.call(organization:, pagination:, filters:).api_logs.first.request_id).to eq(api_log.request_id)

      filters = {http_methods: ["other"]}
      expect(described_class.call(organization:, pagination:, filters:).api_logs).to be_empty
    end
  end

  context "with http_statuses filter" do
    it "returns expected api logs" do
      filters = {http_statuses: [api_log.http_status]}
      expect(described_class.call(organization:, pagination:, filters:).api_logs.first.request_id).to eq(api_log.request_id)

      filters = {http_statuses: ["other"]}
      expect(described_class.call(organization:, pagination:, filters:).api_logs).to be_empty
    end
  end

  context "with api_version filter" do
    it "returns expected api logs" do
      filters = {api_version: api_log.api_version}
      expect(described_class.call(organization:, pagination:, filters:).api_logs.first.request_id).to eq(api_log.request_id)
    end
  end

  context "with request_paths filter" do
    it "returns expected api logs" do
      filters = {request_paths: [api_log.request_path]}
      expect(described_class.call(organization:, pagination:, filters:).api_logs.first.request_id).to eq(api_log.request_id)

      filters = {request_paths: ["other"]}
      expect(described_class.call(organization:, pagination:, filters:).api_logs).to be_empty
    end
  end
end
