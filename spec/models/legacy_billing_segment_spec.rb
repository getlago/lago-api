# frozen_string_literal: true

require "rails_helper"

RSpec.describe LegacyBillingSegment do
  subject(:legacy_segment) { described_class.find(segment_id) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:segment_id) { SecureRandom.uuid }
  let(:at) { Time.current }

  before do
    contract_rate_card
    # Seed an existing legacy row without invoking the read-only model's write API.
    described_class.insert_all!([{ # rubocop:disable Rails/SkipsModelValidations
      id: segment_id, organization_id: organization.id, customer_id: customer.id, contract_id: contract.id,
      contract_rate_card_id: contract_rate_card.id, rate_card_rate_id: rate.id,
      started_at: at, ended_at: at + 1.day, cycle_started_at: at,
      billing_at: at, currency: rate_card.currency, rate_properties: rate.properties,
      status: "pending", proration_ratio: 1, created_at: at, updated_at: at
    }])
  end

  describe "read-only behavior" do
    it "rejects saves, updates, and destroys" do
      expect { legacy_segment.dup.save! }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { legacy_segment.update!(currency: "USD") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { legacy_segment.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
