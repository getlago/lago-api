# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::CommitmentSerializer do
  subject(:serializer) do
    described_class.new(commitment, root_name: 'commitment', includes: %i[taxes])
  end

  let(:commitment) { create(:commitment) }
  let(:tax) { create(:tax, organization: commitment.plan.organization) }
  let(:commitment_applied_tax) { create(:commitment_applied_tax, commitment:, tax:) }

  before { commitment_applied_tax }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['commitment']['lago_id']).to eq(commitment.id)
      expect(result['commitment']['plan_code']).to eq(commitment.plan.code)
      expect(result['commitment']['invoice_display_name']).to eq(commitment.invoice_display_name)
      expect(result['commitment']['commitment_type']).to eq(commitment.commitment_type)
      expect(result['commitment']['amount_cents']).to eq(commitment.amount_cents)
      expect(result['commitment']['interval']).to eq(commitment.plan.interval)
      expect(result['commitment']['created_at']).to eq(commitment.created_at.iso8601)
      expect(result['commitment']['updated_at']).to eq(commitment.updated_at.iso8601)

      expect(result['commitment']['taxes'].count).to eq(1)
      expect(result['commitment']['taxes'].first['commitments_count']).to eq(1)
    end
  end
end
