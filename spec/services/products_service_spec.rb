# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProductsService, type: :service do
  subject { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    let(:product_name) { 'Some product name' }
    let(:billable_metrics) do
      create_list(:billable_metric, 3, organization: organization)
    end

    let(:create_args) do
      {
        name: product_name,
        organization_id: organization.id,
        billable_metric_ids: billable_metrics.map(&:id)
      }
    end

    it 'creates a product' do
      expect { subject.create(**create_args) }
        .to change { Product.count }.by(1)

      product = Product.last

      expect(product.billable_metrics.count).to eq(3)
    end

    context 'with validation error' do
      let(:product_name) { nil }

      it 'returns an error' do
        expect { subject.create(**create_args) }
          .to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context 'with metrics from other organization' do
      let(:billable_metrics) { [create(:billable_metric)] }

      it 'returns an error' do
        result = subject.create(**create_args)

        expect(result).to_not be_success
        expect(result.error).to eq('Billable metrics does not exists')
      end
    end

    context 'when user is not member of the organization' do
      let(:organization) { create(:organization) }

      it 'returns an error' do
        result = subject.create(**create_args)

        expect(result.success?).to be_falsey
        expect(result.error).to eq('not_organization_member')
      end
    end
  end
end
