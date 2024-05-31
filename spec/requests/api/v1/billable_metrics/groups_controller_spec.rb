# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::BillableMetrics::GroupsController, type: :request do
  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }

  describe 'GET /groups' do
    before { billable_metric }

    context 'when billable_metric_id does not exist' do
      it 'returns a not found error' do
        get_with_token(organization, '/api/v1/billable_metrics/unknown/groups')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when billable_metric_id is deleted' do
      it 'returns a not found error' do
        billable_metric.discard
        get_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}/groups")

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when billable_metric_id does not belong to the current organization' do
      it 'returns a not found error' do
        metric = create(:billable_metric)
        get_with_token(organization, "/api/v1/billable_metrics/#{metric.code}/groups")

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when billable metric has no groups' do
      it 'returns an empty array' do
        get_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}/groups")

        expect(response).to have_http_status(:success)
        expect(json[:groups]).to eq([])
      end
    end

    context 'when groups contain one dimension' do
      it 'returns all billable metric\'s active groups' do
        one = create(:group, billable_metric:)
        second = create(:group, billable_metric:)
        create(:group, billable_metric:, deleted_at: Time.current)

        get_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}/groups")

        expect(response).to have_http_status(:success)
        expect(json[:groups]).to contain_exactly(
          {lago_id: one.id, key: one.key, value: one.value},
          {lago_id: second.id, key: one.key, value: second.value}
        )
      end
    end

    context 'when groups contain two dimensions' do
      it 'returns billable metric\'s active children groups' do
        parent = create(:group, billable_metric:)
        children1 = create(:group, billable_metric:, parent_group_id: parent.id)
        children2 = create(:group, billable_metric:, parent_group_id: parent.id)
        create(:group, billable_metric:, parent_group_id: parent.id, deleted_at: Time.current)

        get_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}/groups")

        expect(response).to have_http_status(:success)
        expect(json[:groups]).to contain_exactly(
          {lago_id: children1.id, key: parent.value, value: children1.value},
          {lago_id: children2.id, key: parent.value, value: children2.value}
        )
      end
    end

    context 'with pagination' do
      it 'returns invoices with correct meta data' do
        parent = create(:group, billable_metric:)
        create_list(:group, 2, billable_metric:, parent_group_id: parent.id)

        get_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}/groups?page=1&per_page=1")

        expect(response).to have_http_status(:success)

        expect(json[:groups].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end
  end
end
