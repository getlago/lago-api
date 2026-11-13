# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ScheduleService do
  subject(:result) { described_class.call(customer:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
  let(:initial_billing_at) { contract_rate_card.reload.next_billing_at }

  before { initial_billing_at }

  it "is a successful structural placeholder without changing billing state" do
    expect { result }.not_to change(BillingOperation, :count)
    expect(result).to be_success
    expect(contract_rate_card.reload.next_billing_at).to eq(initial_billing_at)
  end
end
