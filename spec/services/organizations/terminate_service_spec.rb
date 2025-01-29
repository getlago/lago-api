# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organizations::TerminateService, type: :service do
  subject(:result) { described_class.new(organization: organization).call }

  let(:organization) { create(:organization) }

  describe '#call' do
    context 'when organization exists' do
      it 'destroys all associated api keys' do
        create_list(:api_key, 2, organization: organization)

        expect { result }.to change { organization.api_keys.count }.from(3).to(0)
      end

      it 'destroys all associated webhooks and webhook endpoints' do
        create_list(:webhook_endpoint, 2, organization: organization)
        create_list(:webhook, 2, webhook_endpoint: organization.webhook_endpoints.first)

        expect { result }
          .to change { organization.webhooks.count }.from(2).to(0)
          .and change { organization.webhook_endpoints.count }.from(3).to(0)
      end

      it 'returns a successful result' do
        expect(result).to be_success
        expect(result.organization).to eq(organization)
        expect(organization).to be_destroyed
      end
    end

    context 'when organization does not exist' do
      let(:organization) { nil }

      it 'returns a not found failure result' do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("organization_not_found")
      end
    end

    context 'when there is a validation error' do
      before do
        allow(organization).to receive(:destroy!).and_raise(ActiveRecord::RecordInvalid.new(organization))
      end

      it 'returns a record validation failure result' do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end
  end

  # describe '#destroy_all_billable_metrics' do
  #   let(:billable_metric) { create(:billable_metric, organization: organization) }
  #   let(:charge) { create(:charge, billable_metric: billable_metric) }

  #   before do
  #     create_list(:filter_value, 2, charge: charge)
  #     create_list(:filter, 2, charge: charge)
  #     create_list(:applied_tax, 2, charge: charge)
  #   end

  #   it 'destroys all associated charges, filters, filter values, and applied taxes' do
  #     expect { service.send(:destroy_all_billable_metrics) }.to change { charge.filter_values.count }.from(2).to(0)
  #       .and change { charge.filters.count }.from(2).to(0)
  #       .and change { charge.applied_taxes.count }.from(2).to(0)
  #   end
  # end
end
