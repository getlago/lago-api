# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::GroupsController, type: :request do
  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization: organization) }

  describe 'GET /groups' do
    before { billable_metric }

    context 'when billable_metric_id does not exist' do
      it 'returns a not found error' do
        get_with_token(organization, '/api/v1/groups?billable_metric_id=unknown')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when billable_metric_id does not belong to the current organization' do
      it 'returns a not found error' do
        metric = create(:billable_metric)
        get_with_token(organization, "/api/v1/groups?billable_metric_id=#{metric.id}")

        expect(response).to have_http_status(:not_found)
      end
    end

    it 'returns expected billable metric\'s groups' do
      parent = create(:group, billable_metric: billable_metric)
      children1 = create(:group, billable_metric: billable_metric, parent_group_id: parent.id)
      children2 = create(:group, billable_metric: billable_metric, parent_group_id: parent.id)
      create(:group, billable_metric: billable_metric, parent_group_id: parent.id, status: :inactive)

      get_with_token(organization, "/api/v1/groups?billable_metric_id=#{billable_metric.id}")

      expect(response).to have_http_status(:success)
      expect(json[:groups]).to match_array(
        [
          { lago_id: children1.id, key: children1.key, value: children1.value },
          { lago_id: children2.id, key: children2.key, value: children2.value },
        ],
      )
    end

    context 'with pagination' do
      it 'returns invoices with correct meta data' do
        parent = create(:group, billable_metric: billable_metric)
        create_list(:group, 2, billable_metric: billable_metric, parent_group_id: parent.id)

        get_with_token(organization, "/api/v1/groups?billable_metric_id=#{billable_metric.id}&page=1&per_page=1")

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
